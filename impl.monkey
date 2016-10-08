Strict

' Imports:
Import config

Private
	' Testing related:
	'Import regal.util.memory
	Import regal.util.generic
	
	Import util
	Import tree
	Import meta
	Import session
	Import context
Public

' Functions:

' Implementation layer:

' Constant variable(s):
Global code_lengths_order:Int[] = [
	16, 17, 18, 0, 8, 7, 9, 6,
	10, 5, 11, 4, 12, 3, 13, 2,
	14, 1, 15] ' Const ' (19 entries)

' ////// Utility functions \\\\\\

' This builds extra bits and base tables.
Function inf_build_bits_base:Void(bits:ByteArrayView, base:ShortArrayView, delta:Int, first:Int)
	' Build bits table:
	For Local i:= 0 Until delta
		bits.Set(i, 0)
	Next
	
	For Local i:= 0 Until (InfContext.BIT_BASE_LENGTH - delta)
		bits.Set((i + delta), (i / delta))
	Next
	
	' Build base table:
	Local sum:= first
	
	For Local i:= 0 Until InfContext.BIT_BASE_LENGTH
		base.Set(i, sum)
		
		sum += (1 Shl bits.Get(i)) ' Lsl(1, bits.Get(i)) ' GetUnsigned
	Next
End

' This builds fixed huffman trees.
Function inf_build_fixed_trees:Void(lt:InfTree, dt:InfTree)
	' Build fixed length tree.
	For Local i:= 0 Until 7
		lt.lTable.Set(i, 0)
	Next
	
	lt.lTable.Set(7, 24)
	lt.lTable.Set(8, 152)
	lt.lTable.Set(9, 112)
	
	For Local i:= 0 Until 24
		lt.transTable.Set(i, (256 + i))
	Next
	
	For Local i:= 0 Until 144
		lt.transTable.Set((24 + i), i)
	Next
	
	For Local i:= 0 Until 8
		lt.transTable.Set((24 + 144 + i), (280 + i))
	Next
	
	For Local i:= 0 Until 112
		lt.transTable.Set((24 + 144 + 8 + i), (144 + i))
	Next
	
	' Build fixed distance tree:
	For Local i:= 0 Until 5
		dt.lTable.Set(i, 0)
	Next
	
	dt.lTable.Set(5, 32)
	
	For Local i:= 0 Until 32 ' (InfTree.LTABLE_LENGTH * 2)
		dt.transTable.Set(i, i)
	Next
End

' Given an array of code lengths, build a tree.
' 'lengths' is a buffer containing byte values.
Function inf_build_tree:Void(t:InfTree, lengths:IntArrayView, num:Int, _dbg:Bool=False) ' ByteArrayView
	' Optimization potential; dynamic allocations:
	'Local length_data:= New DataBuffer((16+16) * SizeOf_Short)
	Local length_count:= New ShortArrayView(16) ' InfTree.LTABLE_LENGTH ' offs
	Local first_code:= New ShortArrayView(16) ' ' InfTree.LTABLE_LENGTH
	
	Local __lens:= lengths.GetArray()
	
	' Clear the code lengths:
	length_count.Clear()
	
	' Scan symbol length, and sum code length counts:
	For Local i:= 0 Until num
		Local length:= lengths.GetUnsigned(i) ' i ' Get
		
		If (length > 0) Then
			' Increment by one.
			length_count.Increment(length)
		Endif
	Next
	
	Local __lencnt:= length_count.GetArray()
	
	'DebugStop()
	
	' Compute offset table for distribution sort:
	Local total_count:= 0
	
	For Local i:= 1 Until 16 ' InfTree.LTABLE_LENGTH
		total_count += length_count.GetUnsigned(i) ' GetUnsigned
	Next
	
	If (total_count = 0) Then
		DebugStop()
		
		Return ' allow_no_symbols
	Elseif (total_count = 1) Then
		DebugStop()
		
		For Local i:= 0 Until num
			If (lengths.GetUnsigned(i) <> 0) Then
				t.transTable.Set(1, i)
				t.transTable.Set(0, t.transTable.Get(1))
			Endif
		Next
		
		DebugStop()
		
		Return ' 1
	Endif
	
	' Set the first entry to zero.
	first_code.SetUnsigned(0, 0) ' Set
	
	For Local i:= 1 Until 16
		Local value:= Lsl((first_code.GetUnsigned(i - 1) + length_count.GetUnsigned(i - 1)), 1)
		
		first_code.SetUnsigned(i, value)
		
		If ((first_code.GetUnsigned(i) + length_count.GetUnsigned(i)) > Lsl(1, i)) Then
			DebugStop()
			
			Return ' 0
		Endif
	Next
	
	If ((first_code.GetUnsigned(15) + length_count.GetUnsigned(15)) <> Lsl(1, 15)) Then
		DebugStop()
		
		Return ' 0
	Endif
	
	Local __fcode:= first_code.GetArray()
	
	'DebugStop()
	
	Local index:= 0
	
	For Local i:= 1 Until 16
		Local code_limit:= Lsl(1, i)
		
		Local next_code:= (first_code.GetUnsigned(i) + length_count.GetUnsigned(i))
		Local next_index:= (index + (code_limit - first_code.GetUnsigned(i)))
		
		For Local j:= 0 Until num
			If (lengths.GetUnsigned(j) = i) Then
				'Local __trtab:= t.transTable.GetArray()
				
				'DebugStop()
				
				t.transTable.Set(index, j)
				
				index += 1
			Endif
		Next
		
		For Local j:= next_code Until code_limit
			'Local __trtab:= t.transTable.GetArray()
			
			Local NEWVAL:= ~next_index
			
			'DebugStop()
			
			t.transTable.Set(index, NEWVAL)
			
			index += 1
			next_index += 2
		Next
	Next
	
	
	#Rem
	
	' Create code -> symbol translation table (Symbols sorted by code):
	For Local i:= 0 Until num
		Local length:= lengths.Get(i) ' 27 = index 7 ' GetUnsigned
		
		'#If REGAL_INFLATE_DEBUG_OUTPUT
			'Print("lengths[" + i + "]: " + length)
		'#End
		
		If (length > 0) Then
			Local off:= offs.Get(length) ' GetUnsigned
			
			#If REGAL_INFLATE_DEBUG_OUTPUT
				Print("Offset Map: trans["+off+"] {len: "+length+"} = [i: "+i+"]")
			#End
			
			t.transTable.Set(off, i) ' _dbg
			
			offs.Increment(length) ' offs.SetUnsigned(length, (off + 1)) ' off
		Endif
	Next
	
	#End
	
	' Manually discard the offset-buffer.
	'offs.Data.Discard()
End

' ////// Decode functions \\\\\\

' Given a data stream and a tree, decode a symbol.
Function inf_decode_symbol:Int(d:InfSession, t:InfTree, __dbg:Bool=False)
	Local bits_used:= 0
	Local index:= 0
	
	If (__dbg) Then
		DebugStop()
	Endif
	
	Repeat
		Local bit:= d.GetBit()
		
		index += bit
		
		If (t.transTable.Get(index) >= 0) Then
			Exit
		Endif
		
		index = ~t.transTable.Get(index)
	Forever
	
	Local value:= t.transTable.Get(index)
	
	If (__dbg) Then
		Print("[" + index + "]: " + value)
	Endif
	
	Return value
	
	#Rem
	Local sum:= 0
	Local cur:= 0
	Local len:= 0
	
	'DebugStop()
	
	#If REGAL_INFLATE_DEBUG_OUTPUT
		'Print("Decoding symbol...")
	#End
	
	Repeat
		cur = ((2 * cur) + d.GetBit())
		
		len += 1
		
		Local offset:= t.lTable.GetUnsigned(len) ' Get
		
		sum += offset
		cur -= offset
	Until (cur < 0)
	
	Local index:= (sum + cur)
	
	Local symbol:= t.transTable.Get(index)
	
	'#If REGAL_INFLATE_DEBUG_OUTPUT
		If (__dbg) Then
			'DebugStop()
			
			Print("Retrieving symbol from trans[" + index + "] = {" + symbol + "}")
		Endif
	'#End
	
	Return symbol
	#End
End

' Given a data stream, decode dynamic trees from it.
Function inf_decode_trees:Void(d:InfSession, lt:InfTree, dt:InfTree)
	' Optimization potential; dynamic allocations:
	
	' Allocate a temporary length-buffer.
	'Local lengths:= New ByteArrayView(288) ' +32 ' 286 ' IntArrayView ' New Int[288+32] ' (InfTree.TRANSTABLE_LENGTH + (InfTree.LTABLE_LENGTH * 2)) ' Byte[] ' 288+32 (320)
	'Local dists:= New ByteArrayView(32) ' 31
	
	Local hlit:Int, hdist:Int, hclen:Int ' UInt, ...
	
	' Get 5-bit HLIT. (257-286)
	hlit = d.ReadBits(5, 257) ' 1
	
	' Get 5-bit HDIST. (1-32)
	hdist = d.ReadBits(5, 1)
	
	' Get 4-bit HCLEN. (4-19)
	hclen = d.ReadBits(4, 4)
	
	' Set entries of the length buffer(s) to zero:
	'dists.Clear()
	
	#If CONFIG = "debug"
		'lengths.Clear()
	#End
	
	' Build code length tree, temporarily use length tree.
	Local code_tree:= New InfTree(InfTree.TYPE_CODE, True) ' lt
	
	' Read code lengths for code length alphabet:
	For Local i:= 0 Until hclen
		code_tree.lTable.Set(code_lengths_order[i], d.ReadBits(3, 0))
	Next
	
	#Rem
		Local _test:= 0
		
		While (_test < hclen)
			' Read 3-bit code lengths. (0-7)
			code_tree.lTable.Set(code_lengths_order[_test], d.ReadBits(3, 0))
			
			_test += 1
		Wend
		
		While (_test < 19)
			code_tree.lTable.Set(code_lengths_order[_test], 0)
			
			_test += 1
		Wend
	#End
	
	'DebugStop()
	
	Local in_pos:= d.source.Position
	Local out_pos:= d.destination.Position
	
	inf_build_tree(code_tree, code_tree.lTable, 19) ' code_lengths_order.Length
	
	in_pos = d.source.Position
	out_pos = d.destination.Position
	
	Local code_l:= code_tree.lTable.GetArray()
	Local code_t:= code_tree.transTable.GetArray()
	
	'DebugStop()
	
	inf_decode_trees_impl(code_tree, d, lt.lTable, hlit)
	inf_decode_trees_impl(code_tree, d, dt.lTable, hdist)
	
	' Build dynamic tree:
	
	' Build literal lengths.
	inf_build_tree(lt, lt.lTable, hlit, True) ' 1
	
	' Build distance codes.
	inf_build_tree(dt, dt.lTable, hdist)
End

Function inf_decode_trees_impl:Void(code_tree:InfTree, d:InfSession, lengths:IntArrayView, count:Int, offset:Int=0) ' ByteArrayView
	Local num:= offset
	
	DebugStop()
	
	' Decode code lengths for the dynamic trees:
	While (num < count)
		' Load a symbol.
		Local sym:= inf_decode_symbol(d, code_tree)
		
		Select (sym)
			Case 16
				' Copy previous code length 3-6 times (Read 2 bits):
				Local prev:= lengths.GetUnsigned(num - 1) ' Get
				
				Local length:= d.ReadBits(2, 3)
				
				While (length > 0)
					lengths.Set(num, prev)
					
					num += 1
					
					length -= 1
				Wend
			Case 17
				' Report code length 0 for 3-10 times (Read 3 bits):
				Local length:= d.ReadBits(3, 3)
				
				While (length > 0)
					lengths.Set(num, 0)
					
					num += 1
					
					length -= 1
				Wend
			Case 18
				' Report code length 0 for 11-138 times (Read 7 bits):
				Local length:= d.ReadBits(7, 11)
				
				While (length > 0)
					lengths.Set(num, 0)
					
					num += 1
					
					length -= 1
				Wend
			Default
				lengths.Set(num, sym)
				
				num += 1
		End Select
	Wend
End

' ////// Block inflate functions \\\\\\

' Given a stream and two trees, inflate a block of data.
Function inf_inflate_block_data:Int(context:InfContext, d:InfSession, lt:InfTree, dt:InfTree)
	Local real_pos:= d.destination.Position
	
	If (real_pos Mod 256 = 0) Then ' real_pos <> 0
		'DebugStop()
	Endif
	
	'DebugStop()
	
	If (d.curlen = 0) Then
		#If REGAL_INFLATE_DEBUG_OUTPUT
			'Print("// Huffman symbol \\")
		#End
		
		Local sym:= inf_decode_symbol(d, lt, True)
		
		'#If REGAL_INFLATE_DEBUG_OUTPUT
			'Print("Huffman symbol: " + sym)
		'#End
		
		'DebugStop()
		
		If (sym = 0) Then ' 256 = 255 (Zero added for some reason)
			'Print("POSITION: " + real_pos)
			
			DebugStop()
		Endif
		
		' Literal value:
		If (sym < 256) Then
			#If REGAL_INFLATE_DEBUG_OUTPUT
				Print("{LIT VALUE}")
			#End
			
			d.Put(sym)
			
			Return INF_OK
		Endif
		
		' End-of-block:
		If (sym = 256) Then
			Return INF_DONE
		Endif
		
		' This is an entry from our sliding dictionary:
		sym -= 257
		
		' Possibly get more bits from length code.
		d.curlen = d.ReadBits(context.length_bits.Get(sym), context.length_base.Get(sym)) ' context.length_base.GetUnsigned(sym)
		
		Local dist:= inf_decode_symbol(d, dt)
		
		' Possibly get more bits from distance code.
		Local offs:= d.ReadBits(context.dist_bits.Get(dist), context.dist_base.Get(dist)) ' context.dist_base.GetUnsigned(dist)
		
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
		Local value:= (d.dict_ring.PeekByte(d.lzOff) & $FF)
		
		d.Put(value)
		
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
		length = d.source.ReadShort()
		invLength = d.source.ReadShort()
		
		Local pos:= d.source.Position
		
		DebugStop()
		
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
	d.bFinal = d.GetBit() ' > 0
	
	If (d.bFinal) Then
		DebugStop()
	Endif
	
	' Read the block type. (2 bits)
	d.bType = d.ReadBits(2, 0)
	
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