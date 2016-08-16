Strict

#Rem
	A Monkey port of 'Tiny Inflate' by Joergen Ibsen.
#End

' Preprocessor related:

' This enables use of 'regal.ioutil'.
#REGAL_INFLATE_IOUTIL = True

#If REGAL_INFLATE_IOUTIL
	' This enables 'regal.ioutil' extensions.
	#REGAL_INFLATE_IOUTIL_PBS_EXT = True
#End

'#REGAL_INFLATE_RUNTIME_TABLES = True

#REGAL_INFLATE_DEBUG_OUTPUT = True

Public
	' Imports:
	Import brl.stream
	Import brl.databuffer
Private
	' Imports:
	#If Not REGAL_INFLATE_RUNTIME_TABLES
		Import regal.util.memory
	#End
	
	Import regal.sizeof
	Import regal.byteorder
	
	#If Not REGAL_INFLATE_DISABLE_ALT_SHIFT
		Import regal.hash
	#Else
		Import regal.hash.adler32
		Import regal.hash.crc32
	#End
	
	#If REGAL_INFLATE_IOUTIL ' REGAL_INFLATE_IOUTIL_PBS_EXT
		Import regal.ioutil.publicdatastream
		'Import regal.ioutil.repeater
	#End
Public
	' Constant variable(s):
	
	' Response-code definitions:
	Const INF_OK:= 0
	Const INF_DONE:= 1
	Const INF_DATA_ERROR:= -3
	Const INF_CHKSUM_ERROR:= -4
	'Const INF_DEST_OVERFLOW:= -5
	
	' Checksum types:
	Const INF_CHECKSUM_NONE:= 0
	Const INF_CHECKSUM_ADLER32:= 1
	Const INF_CHECKSUM_CRC32:= 2
Private
	' Functions:
	
	' Utility layer:
	
	' This converts a 2-byte stride into bytes.
	Function Short_To_Byte_Space:Int(index:Int)
		Return (index * SizeOf_Short)
	End
	
	' This converts an "address" (Real offset) to an index with a 2-byte stride.
	Function Byte_To_Short_Space:Int(addr:Int) ' length:Int
		Return (addr / SizeOf_Short)
	End
	
	Function Get_Short:Int(buffer:DataBuffer, index:Int) ' Short
		Return (buffer.PeekShort(Short_To_Byte_Space(index)) & $FFFF)
	End
	
	Function Get_Byte:Int(buffer:DataBuffer, index:Int) ' Byte
		Return (buffer.PeekByte(index) & $FF)
	End
	
	Function Set_Short:Void(buffer:DataBuffer, index:Int, value:Int) ' Short
		buffer.PokeShort(Short_To_Byte_Space(index), (value & $FFFF))
	End
	
	Function Set_Byte:Void(buffer:DataBuffer, index:Int, value:Int) ' Byte
		buffer.PokeByte(index, (value & $FF))
	End
	
	Function SeekForward:Int(s:Stream, num_bytes:Int)
		Local new_pos:= (s.Position + num_bytes)
		
		s.Seek(new_pos)
		
		Return new_pos
	End
	
	Function SeekBackward:Int(s:Stream, num_bytes:Int)
		Local new_pos:= (s.Position - num_bytes)
		
		s.Seek(new_pos)
		
		Return new_pos
	End
	
	' Debugging related:
	#Rem
	Function Get_Byte:Int(values:Int[], index:Int)
		Return (values[index] & $FF)
	End
	
	Function Set_Byte:Void(buffer:Int[], index:Int, value:Int)
		buffer[index] = (value & $FF)
	End
	#End
	
	' Implementation layer:
	
	' Constant variable(s):
	Global clcidx:Int[] = [
		16, 17, 18, 0, 8, 7, 9, 6,
		10, 5, 11, 4, 12, 3, 13, 2,
		14, 1, 15] ' Const ' (19 entries)
	
	' The type-adjusted lengths of the "bit" and "base" buffers used internally.
	Const BIT_BASE_LENGTH:= 30
	
	' ////// Utility functions \\\\\\
	
	' This builds extra bits and base tables.
	Function inf_build_bits_base:Void(bits__bytes:DataBuffer, base__shorts:DataBuffer, delta:Int, first:Int)
		' Build bits table:
		For Local i:= 0 Until delta
			Set_Byte(bits__bytes, i, 0)
		Next
		
		For Local i:= 0 Until (BIT_BASE_LENGTH - delta)
			Set_Byte(bits__bytes, (i + delta), (i / delta))
		Next
		
		' Build base table:
		Local sum:= first
		
		For Local i:= 0 Until BIT_BASE_LENGTH
			Set_Short(base__shorts, i, sum)
			
			sum += (1 Shl Get_Byte(bits__bytes, i)) ' Lsl(1, Get_Byte(bits__bytes, i))
		Next
	End
	
	' This builds fixed huffman trees.
	Function inf_build_fixed_trees:Void(lt:InfTree, dt:InfTree)
		' Build fixed length tree.
		For Local i:= 0 Until 7 ' 8 bits.
			lt.Set_lTable(i, 0)
		Next
		
		lt.Set_lTable(7, 24)
		lt.Set_lTable(8, 152)
		lt.Set_lTable(9, 112)
		
		For Local i:= 0 Until 24
			lt.Set_transTable(i, (256 + i))
		Next
		
		For Local i:= 0 Until 144
			lt.Set_transTable((24 + i), i)
		Next
		
		For Local i:= 0 Until 8
			lt.Set_transTable((24 + 144 + i), (280 + i))
		Next
		
		For Local i:= 0 Until 112
			lt.Set_transTable((24 + 144 + 8 + i), (144 + i))
		Next
		
		' Build fixed distance tree:
		For Local i:= 0 Until 5
			dt.Set_lTable(i, 0)
		Next
		
		dt.Set_lTable(5, 32)
		
		For Local i:= 0 Until 32 ' (InfTree.LTABLE_LENGTH * 2)
			dt.Set_transTable(i, i)
		Next
	End
	
	' Given an array of code lengths, build a tree.
	' 'lengths' is a buffer containing byte values.
	Function inf_build_tree:Void(t:InfTree, lengths:DataBuffer, num:Int, offset:Int) ' offset:Int=0 ' Size_t ' Int[] ' Byte[]
		' Optimization potential; dynamic allocation.
		Local offs:= New Int[InfTree.LTABLE_LENGTH] ' t.lTable_Length ' 16
		
		' Clear code length count table:
		For Local i:= 0 Until InfTree.LTABLE_LENGTH ' offs.Length ' 16
			t.Set_lTable(i, 0)
		Next
		
		' Scan symbol length, and sum code length counts:
		For Local i:= 0 Until num
			Local position:= Get_Byte(lengths, (i + offset))
			
			Local currentValue:= t.Get_lTable(position)
			
			' Increment by one.
			t.Set_lTable(position, (currentValue + 1))
		Next
		
		' Set the first entry to zero.
		t.Set_lTable(0, 0)
		
		' Compute offset table for distribution sort:
		Local sum:= 0
		
		For Local i:= 0 Until offs.Length ' 16
			offs[i] = sum ' & $FFFF
			
			sum += t.Get_lTable(i)
		Next
		
		' Create code -> symbol translation table (Symbols sorted by code):
		For Local i:= 0 Until num
			Local length:= Get_Byte(lengths, (i + offset))
			
			If (length) Then ' > 0
				Local offset:= offs[length]
				
				t.Set_transTable(offset, i)
				
				offs[length] += 1 ' offset
			Endif
		Next
	End
	
	' ////// Decode functions \\\\\\
	
	' Get one bit from source stream.
	Function inf_getbit:Int(d:InfSession) ' Bool
		Local bit:Int '  UInt
		
		' Check if 'tag' is empty:
		Local bitCount:= d.bitCount
		
		d.bitCount -= 1
		
		If (Not bitCount) Then ' <= 0
			' Load next tag:
			d.tag = d.ReadByte()
			
			d.bitCount = 7 ' (Zero counts)
		Endif
		
		' Shift bit out of tag:
		bit = d.tag & $01
		
		d.tag Shr= 1 ' Lsr(d.tag, 1)
		
		Return bit
	End
	
	' Read a 'num' bit-value from a stream and add 'base'.
	Function inf_read_bits:Int(d:InfSession, num:Int, base:Int) ' UInt
		Local value:= 0 ' UInt
		
		' Read 'num' bits:
		If (num) Then ' > 0
			Local limit:= (1 Shl num) ' UInt ' Lsl(1, num)
			
			Local mask:Int = 1 ' UInt
			
			While (mask < limit)
				If (inf_getbit(d)) Then
					value += mask
				Endif
				
				mask *= 2
				'mask = Lsl(mask, 1)
			Wend
		Endif
		
		Return (value + base)
	End
	
	' Given a data stream and a tree, decode a symbol.
	Function inf_decode_symbol:Int(d:InfSession, t:InfTree)
		Local sum:= 0
		Local cur:= 0
		Local len:= 0
		
		Repeat
			cur = (2*cur + inf_getbit(d))
			
			len += 1
			
			Local offset:= t.Get_lTable(len)
			
			sum += offset
			cur -= offset
		Until (cur < 0)
		
		Return t.Get_transTable(sum + cur)
	End
	
	' Given a data stream, decode dynamic trees from it.
	Function inf_decode_trees:Void(d:InfSession, lt:InfTree, dt:InfTree)
		' Optimization potential; dynamic allocations:
		
		' Allocate a temporary length-buffer.
		Local lengths:= New DataBuffer(288+32) ' New Int[288+32] ' (InfTree.TRANSTABLE_LENGTH + (InfTree.LTABLE_LENGTH * 2)) ' Byte[]
		
		Local hlit:Int, hdist:Int, hclen:Int ' UInt, ...
		
		' Get 5-bit HLIT. (257-286)
		hlit = inf_read_bits(d, 5, 257) ' 1
		
		' Get 5-bit HDIST. (1-32)
		hdist = inf_read_bits(d, 5, 1)
		
		' Get 4-bit HCLEN. (4-19)
		hclen = inf_read_bits(d, 4, 4)
		
		For Local i:= 0 Until 19
			Set_Byte(lengths, i, 0)
		Next
		
		' Read code lengths for code length alphabet:
		For Local i:= 0 Until hclen
			' Get 3 bits code length. (0-7)
			Local clen:= inf_read_bits(d, 3, 0)
			
			Local index:= clcidx[i]
			
			Set_Byte(lengths, index, clen)
		Next
		
		' Build code length tree, temporarily use length tree.
		inf_build_tree(lt, lengths, 19, 0) ' clcidx.Length
		
		' Decode code lengths for the dynamic trees:
		Local num:= 0
		
		While (num < (hlit + hdist))
			' Load a symbol.
			Local sym:= inf_decode_symbol(d, lt)
			
			Select (sym)
				Case 16
					' Copy previous code length 3-6 times (Read 2 bits):
					Local prev:= Get_Byte(lengths, (num - 1))
					
					Local length:= inf_read_bits(d, 2, 3)
					
					While (length) ' > 0
						Set_Byte(lengths, num, prev)
						
						num += 1
						
						length -= 1
					Wend
				Case 17
					' Report code length 0 for 3-10 times (Read 3 bits):
					Local length:= inf_read_bits(d, 3, 3)
					
					While (length) ' > 0
						Set_Byte(lengths, num, 0)
						
						num += 1
						
						length -= 1
					Wend
				Case 18
					' Report code length 0 for 11-138 times (Read 7 bits):
					Local length:= inf_read_bits(d, 7, 11)
					
					While (length) ' > 0
						Set_Byte(lengths, num, 0)
						
						num += 1
						
						length -= 1
					Wend
				Default
					Set_Byte(lengths, num, sym)
					
					num += 1
			End Select
		Wend
		
		' Build dynamic treee:
		inf_build_tree(lt, lengths, hlit, 0)
		inf_build_tree(dt, lengths, hdist, hlit)
		
		' With the trees built, discard our temporary length-buffer.
		'lengths.Discard()
	End
	
	' ////// Block inflate functions \\\\\\
	
	' Given a stream and two trees, inflate a block of data.
	Function inf_inflate_block_data:Int(context:InfContext, d:InfSession, lt:InfTree, dt:InfTree)
		If (d.curlen = 0) Then
			Local sym:= inf_decode_symbol(d, lt)
			
			#If REGAL_INFLATE_DEBUG_OUTPUT
				'Print("Huffman symbol: " + sym)
			#End
			
			' Literal value:
			If (sym < 256) Then
				d.Put(sym)
				
				Return INF_OK
			Endif
			
			' End-of-block:
			If (sym = 256) Then
				Return INF_DONE
			Endif
			
			Local offs:Int ' UInt
			Local dist:Int
			
			' This is an entry from our sliding dictionary:
			sym -= 257
			
			' Possibly get more bits from length code.
			d.curlen = inf_read_bits(d, Get_Byte(context.length_bits, sym), Get_Short(context.length_base, sym)) ''''
			
			dist = inf_decode_symbol(d, dt)
			
			' Possibly get more bits from distance code.
			offs = inf_read_bits(d, Get_Byte(context.dist_bits, dist), Get_Short(context.dist_base, dist));
			
			If (d.dict_ring) Then
				d.lzOff = (d.dict_idx - offs)
				
				If (d.lzOff < 0) Then
					d.lzOff += d.dict_size
				Endif
			Else
				d.lzOff = -offs
			Endif
		Endif
		
		' Copy the next byte from the dictionary entry requested:
		If (d.dict_ring) Then
			d.Put(Get_Byte(d.dict_ring, d.lzOff))
			
			d.lzOff += 1
			
			If (d.lzOff = d.dict_size) Then
				d.lzOff = 0
			Endif
		Else
			'DebugStop()
			
			' Grab a previously written byte:
			Local current_pos:= d.destination.Position
			
			SeekForward(d.destination, d.lzOff)
			
			Local value:= d.destination.ReadByte()
			
			d.destination.Seek(current_pos)
			
			d.destination.WriteByte(value)
		Endif
		
		d.curlen -= 1
		
		Return INF_OK
	End
	
	' Inflate an uncompressed block of data.
	Function inf_inflate_uncompressed_block:Int(__context:InfContext, d:InfSession)
		If (d.curlen = 0) Then
			Local length:Int, invLength:Int ' UInt
			
			' Get the length:
			'length = d.source.ReadShort()
			'invLength = d.source.ReadShort()
			
			' This may not be endian-coherent, but it works:
			length = (d.ReadByte() + 256 * d.ReadByte())
			invLength = (d.ReadByte() + 256 * d.ReadByte())
			
			If (length <> (~invLength & $0000FFFF)) Then
				DebugStop()
				
				' Tell the user something's wrong.
				Return INF_DATA_ERROR
			Endif
			
			d.curlen = (length + 1)
			
			' Make sure we start the next block on a byte boundary.
			d.bitCount = 0
		Endif
		
		d.curlen -= 1
		
		If (d.curlen = 0) Then
			Return INF_DONE
		Endif
		
		' Transfer one byte.
		d.Put(d.ReadByte())
		
		' Give the user the expected response.
		Return INF_OK
	End
	
	' Extensions:
	Function inf_begin_block:Void(d:InfSession)
		' Read the final block flag.
		d.bFinal = inf_getbit(d) ' > 0
		
		' Read the block type. (2 bits)
		d.bType = inf_read_bits(d, 2, 0)
		
		#If REGAL_INFLATE_DEBUG_OUTPUT
			Print("Started a new block { Type: " + d.bType + ", Final: " + d.bFinal + " }")
		#End
		
		Select (d.bType)
			Case 1
				' Build fixed huffman trees.
				inf_build_fixed_trees(d.lTree, d.dTree)
			Case 2
				' Decode trees from stream.
				inf_decode_trees(d, d.lTree, d.dTree)
		End Select
	End
	
	' Hashing functions:
	Function inf_adler32:Int(data:DataBuffer, length:Int, offset:Int, prev_sum:Int) ' offset:Int=0, prev_sum:Int=0 ' UInt
		Return Adler32(data, length, offset, prev_sum)
	End
	
	Function inf_crc32:Int(data:DataBuffer, length:Int, offset:Int, prev_sum:Int)
		Return CRC32(data, length, offset, prev_sum) ' False
	End
	
	' This generates an Adler32 hash using the output-stream of 'data'.
	' The '__safe' argument is used internally, and acts as a hint for memory optimizations.
	' This argument should not be changed under normal circumstances.
	Function inf_adler32:Int(data:InfSession, start_pos:Int, length:Int, prev_sum:Int, __safe:Bool=False) ' UInt
		Local view:= data.DestinationAsMemoryView(start_pos, __safe)
		
		Local offset:= data.GetMemoryViewOffset(view)
		
		If (data.__IsProtectedMemoryView(view)) Then
			offset += start_pos
		Endif
		
		Local result:= inf_adler32(view, length, offset, prev_sum)
		
		data.ReleaseMemoryView(view)
		
		Return result
	End
	
	' This generates a CRC32 hash using the output-stream of 'data'.
	' The '__safe' argument is used internally, and acts as a hint for memory optimizations.
	' This argument should not be changed under normal circumstances.
	Function inf_crc32:Int(data:InfSession, start_pos:Int, length:Int, prev_sum:Int, __safe:Bool=False) ' UInt
		Local view:= data.DestinationAsMemoryView(start_pos, __safe)
		
		Local offset:= data.GetMemoryViewOffset(view)
		
		If (data.__IsProtectedMemoryView(view)) Then
			offset += start_pos
		Endif
		
		Local result:= inf_crc32(view, length, offset, prev_sum)
		
		data.ReleaseMemoryView(view)
		
		Return result
	End
	
	' Classes:
	
	Class InfTree
		Private
			' Constant variable(s):
			Const LTABLE_LENGTH:= 16
			Const TRANSTABLE_LENGTH:= 288 ' 256+32
		Public
			' Methods:
			Method Get_lTable:Int(index:Int) ' Short
				Return Get_Short(lTable, index)
			End
			
			Method Get_transTable:Int(index:Int) ' Short
				Return Get_Short(transTable, index)
			End
			
			Method Set_lTable:Void(index:Int, value:Int) ' Short
				Set_Short(lTable, index, value)
			End
			
			Method Set_transTable:Void(index:Int, value:Int) ' Short
				Set_Short(transTable, index, value)
			End
			
			' Properties:
			Method lTable_Length:Int() Property
				Return LTABLE_LENGTH ' Byte_To_Short_Space(lTable.Length)
			End
			
			Method transTable_Length:Int() Property
				Return TRANSTABLE_LENGTH ' Byte_To_Short_Space(transTable.Length)
			End
		Private
			' Fields:
			Field lTable:DataBuffer = New DataBuffer(LTABLE_LENGTH * SizeOf_Short) ' Short[]
			Field transTable:DataBuffer = New DataBuffer(TRANSTABLE_LENGTH * SizeOf_Short) ' Short[]
	End
Public
	' Classes:
	
	' This holds information about the state of an inflation task,
	' and all required inputs used to perform the operations.
	Class InfSession ' Final
		Public
			' Constant variable(s):
			
			' This dictionary size was chosen because it is the largest required to decode a PNG file.
			Const Default_Dictionary_Size:= (32 * 1024) ' * 1024
			
			' Constructor(s):
			Method New(source:Stream, destination:Stream, destSize:Int, dictionary_size:Int=Default_Dictionary_Size)
				Construct_InfSession(source, destination, destSize, dictionary_size)
				
				#If REGAL_INFLATE_IOUTIL_PBS_EXT
					Self.__bufferStream = PublicDataStream(destination)
				#End
			End
			
			#If False ' REGAL_INFLATE_IOUTIL_PBS_EXT
				Method New(source:Stream, destination:PublicDataStream, destSize:Int, dictionary_size:Int=Default_Dictionary_Size)
					Construct_InfSession(source, destination, destSize, dictionary_size)
					
					Self.__bufferStream = destination
				End
			#End
		Private ' Protected
			' Constructor(s):
			Method Construct_InfSession:Void(source:Stream, destination:Stream, destSize:Int, dictionary_size:Int)
				Self.source = source
				Self.destination = destination
				
				Self.destSize = destSize
				
				If (dictionary_size > 0) Then
					Self.dict_ring = New DataBuffer(dictionary_size)
					'Self.dict_size = dictionary_size
				EndIf
			End
		Public
			' Methods:
			Method ReadByte:Int()
				Return (source.ReadByte() & $FF)
			End
			
			' This directly writes a byte to the 'destination' stream.
			Method WriteByte:Int(value:Int)
				Local out_value:= (value & $FF)
				
				destination.WriteByte(out_value)
				
				Return out_value
			End
			
			' This writes a byte to the 'destination', and
			' stores that value in an internal ring-buffer, if available.
			Method Put:Void(value:Int)
				value = WriteByte(value)
				
				If (dict_ring) Then ' <> Null
					dict_ring.PokeByte(dict_idx, value)
					
					dict_idx += 1
					
					If (dict_idx = dict_size) Then
						dict_idx = 0
					Endif
				Endif
			End
			
			' Memory-access layer:
			
			' This presents the 'destination' object in read-only 'DataBuffer' form.
			' This data may or may not be safe to modify. To reduce undefined
			' behavior, please do not modify or release this buffer in any way.
			' To release this 'memory-view' properly, please call 'ReleaseMemoryView'.
			' Please use 'GetMemoryViewOffset' as a base offset when reading from this buffer.
			Method DestinationAsMemoryView:DataBuffer(origin:Int, safe:Bool=False)
				#If REGAL_INFLATE_IOUTIL_PBS_EXT
					If (Not safe) Then
						If (__bufferStream <> Null) Then
							Return __bufferStream.Data
						Endif
					Endif
				#End
				
				Local current_pos:= destination.Position
				
				destination.Seek(origin)
				
				Local memory:= destination.ReadAll()
				
				destination.Seek(current_pos)
				
				Return memory
			End
			
			Method ReleaseMemoryView:Void(view:DataBuffer)
				#If REGAL_INFLATE_IOUTIL_PBS_EXT
					' Check if this memory should be protected:
					If (__bufferStream <> Null) Then
						If (__bufferStream.Data = view) Then
							Return
						Endif
					Endif
				#End
				
				view.Discard()
			End
			
			' This returns the correct offset 'view' should be used at.
			Method GetMemoryViewOffset:Int(view:DataBuffer) ' UInt
				#If REGAL_INFLATE_IOUTIL_PBS_EXT
					If (__bufferStream <> Null And (__bufferStream.Data = view)) Then
						Return __bufferStream.Offset
					Endif
				#End
				
				Return 0
			End
			
			' Extensions:
			Method __IsProtectedMemoryView:Bool(view:DataBuffer)
				#If REGAL_INFLATE_IOUTIL_PBS_EXT
					If (__bufferStream <> Null And (__bufferStream.Data = view)) Then
						Return True
					Endif
				#End
				
				Return False
			End
		'Protected
			' Fields:
			Field source:Stream
			Field destination:Stream
		Private
			' This is an extension that uses 'PublicDataStream'
			' to get around unneeded copy/read operations.
			' This is only valid if 'INFLATE_IOUTIL' is enabled.
			#If REGAL_INFLATE_IOUTIL_PBS_EXT
				Field __bufferStream:PublicDataStream = Null
			#End
		Private ' Protected
			' Fields:
			Field tag:Int = 0
			Field bitCount:Int = 0
			
			' Total output size.
			Public
			Field destSize:Int ' UInt
			Private
			
			'Field destRemaining:Int ' UInt
			
			' Checksum value based represented using the method specified by 'checksum_type'.
			Field checksum:Int = 0
			
			' The type of checksum used for integrity checks.
			Field checksum_type:Int = INF_CHECKSUM_ADLER32
			
			' These represent the current block header:
			Field bType:Int = -1
			Field bFinal:Int = 0 ' Bool
			
			Field curlen:Int = 0
			
			' Dictionary:
			'Field dictionary:PublicDataStream
			
			' The current dictionary offset.
			Field lzOff:Int = 0
			
			' A dictionary used to reduce seeking operations.
			Field dict_ring:DataBuffer
			
			' This may be removed at some point.
			'Field dict_size:Int ' UInt
			
			' The current index in the dictionary ring-buffer.
			Field dict_idx:Int = 0 ' UInt
			
			' Trees:
			Field lTree:InfTree = New InfTree()
			Field dTree:InfTree = New InfTree()
			
			' Properties:
			Method dict_size:Int() Property ' UInt
				If (Not dict_ring) Then ' = Null
					Return 0
				Endif
				
				Return dict_ring.Length
			End
	End
	
	' This stores static/temporary data used to perform inflation on a stream.
	' This data is largely a composite of a session's working-set.
	Class InfContext
		Public ' Protected
			' Fields:
			
			' Extra bits and base tables for length codes:
			Field length_bits:= New DataBuffer(BIT_BASE_LENGTH) ' Byte[]
			Field length_base:= New DataBuffer(BIT_BASE_LENGTH * SizeOf_Short) ' Short[]
			
			' Extra bits and base tables for distance codes:
			Field dist_bits:= New DataBuffer(BIT_BASE_LENGTH) ' Byte[]
			Field dist_base:= New DataBuffer(BIT_BASE_LENGTH * SizeOf_Short) ' Short[]
		Public
			' Constructor(s):
			Method New()
				#If REGAL_INFLATE_RUNTIME_TABLES
					' Build extra bits and base tables:
					inf_build_bits_base(length_bits, length_base, 4, 3)
					inf_build_bits_base(dist_bits, dist_base, 2, 1)
					
					' Fix a special case:
					Set_Byte(length_bits, 28, 0)
					Set_Short(length_base, 28, 258)
				#Else
					' Lengths:
					SetBytes(length_bits, [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5,  0, 0]) ' 0, 6
					SetShorts(length_base, [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258,  0]) ' 323
					
					' Distances:
					SetBytes(dist_bits, [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13])
					SetShorts(dist_base, [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577])
				#End
			End
	End
	
	' Functions:
	
	' The destination must support read-write seeking.
	' This means reading back serialized data is required.
	' For 'FileStream' objects, this requires the "u" or "a" access modes.
	Function Inflate:Int(context:InfContext, d:InfSession) ' sourceLen:Int ' uncompress
		Local res:Int
		
		' Start a new block:
		
		' Make sure this is our first pass:
		If (d.bType = -1) Then
			inf_begin_block(d)
		Endif
		
		Repeat
			' Process the current block:
			Select (d.bType)
				Case 0
					DebugStop()
					
					' "Inflate" uncompressed block.
					res = inf_inflate_uncompressed_block(context, d)
				Case 1, 2
					res = inf_inflate_block_data(context, d, d.lTree, d.dTree)
				Default
					Return INF_DATA_ERROR
			End Select
			
			#Rem
				If (d.bFinal) Then
					Local src_pos:= d.source.Position
					Local dst_pos:= d.destination.Position
					
					If (dst_pos = 45439) Then
						DebugStop()
					Endif
				Endif
			#End
			
			If (res = INF_DONE And Not d.bFinal) Then
				inf_begin_block(d)
				
				Continue
			Elseif (res <> INF_OK) Then
				DebugStop()
				
				Return res
			Endif
			
			d.destSize -= 1
		Until (d.destSize <= 0) ' Not d.destSize ' Forever ' Until (d.source.Eof())
		
		Return INF_OK
	End
	
	#Rem
		This inflates using the parameters specified, and outputs
		a hash of the type specified by 'data.checksum_type'.
		
		The output stream of 'data' must support full I/O manipulation (Reading/peeking).
		
		Good examples of this are things like 'FileStreams' opened with "u" access-rights,
		or 'PublicDataStream' objects, which support both chronological review, or memory-mapping extensions.
	#End
	
	Function Inflate_Checksum:Int(context:InfContext, data:InfSession, bigendian_input:Bool=False)
		Local start_pos:= data.destination.Position
		
		Local result:= Inflate(context, data)
		
		' Magic number: 0 (Requires error-codes to be negative)
		If (result < 0) Then
			Return result
		Endif
		
		Local end_pos:= data.destination.Position
		
		' Check how many bytes we've written.
		Local block_len:= (end_pos - start_pos) ' data.destLen
		
		data.destination.Seek(start_pos)
		
		Select (data.checksum_type)
			Case INF_CHECKSUM_ADLER32
				data.checksum = inf_adler32(data, start_pos, block_len, data.checksum)
			Case INF_CHECKSUM_CRC32
				data.checksum = inf_crc32(data, start_pos, block_len, data.checksum)
		End Select
		
		data.destination.Seek(end_pos)
		
		' Check if we're done, and if so, read the checksum and check it:
		If (result = INF_DONE) Then
			Local checksum_raw:= data.source.ReadInt() ' & $FFFFFFFF
			
			Select (data.checksum_type)
				Case INF_CHECKSUM_ADLER32
					Local checksum:Int ' UInt
					
					If (Not bigendian_input) Then
						checksum = NToHL(checksum_raw)
					Else
						checksum = checksum_raw
					Endif
					
					If (data.checksum <> checksum) Then
						DebugStop()
						
						Return INF_DATA_ERROR
					Endif
				Case INF_CHECKSUM_CRC32
					Local checksum:Int ' UInt
					
					If (bigendian_input) Then
						checksum = HToNL(checksum_raw)
					Else
						checksum = checksum_raw
					Endif
					
					If (~data.checksum <> checksum) Then
						Return INF_CHKSUM_ERROR
					Endif
					
					' Reserved: Uncompressed size.
					Local __size:= data.source.ReadInt()
			End Select
		Endif
		
		Return result
	End
	
	' This parses the 2-byte header of a 'zlib' deflation stream.
	Function InfParseZlibHeader:Int(data:InfSession)
		Local cmf:Int, flg:Int
		
		' Read the header from the input-stream.
		cmf = data.ReadByte()
		flg = data.ReadByte()
		
		' Check the format:
		
		' Check aginst the 'checksum':
		If (((256*cmf) + flg) Mod 31) Then ' > 0
			Return INF_DATA_ERROR
		Endif
		
		' Make sure the method is deflate:
		If ((cmf & $0F) <> 8) Then
			' This was not encoded using deflate.
			Return INF_DATA_ERROR
		Endif
		
		Local cinfo:= Lsr(cmf, 4)
		
		' Check if the window size is valid:
		If (cinfo > 7) Then ' Shr
			' This cannot be held within a standard 32K dictionary.
			Return INF_DATA_ERROR
		Endif
		
		' Check that there's no preset dictionary:
		If ((flg & $20)) Then ' > 0
			Return INF_DATA_ERROR
		Endif
		
		' Initialize checksum behavior:
		
		' Set the checksum type to Adler32.
		data.checksum_type = INF_CHECKSUM_ADLER32
		
		' Set the initial value of our checksum.
		data.checksum = 1
		
		Return cinfo ' Lsr(cmf, 4) ' Shr ' & $FF
	End