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
Global clcidx:Int[] = [
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
Function inf_build_tree:Void(t:InfTree, lengths:ByteArrayView, num:Int, offset:Int, _dbg:Bool=False) ' offset:Int=0 ' Size_t ' Int[] ' Byte[] ' IntArrayView
	' Optimization potential; dynamic allocation.
	Local offs:= New ShortArrayView(InfTree.LTABLE_LENGTH) ' New Int[InfTree.LTABLE_LENGTH] ' 16 ' Short[] ' UShort[]
	
	' Clear the code lengths:
	For Local i:= 0 Until InfTree.LTABLE_LENGTH ' t.lTable_Length ' offs.Length ' 16
		t.lTable.Set(i, 0)
	Next
	
	' Scan symbol length, and sum code length counts:
	'For Local i:= offset Until (offset+num)
	For Local i:= 0 Until num
		Local length:= lengths.GetUnsigned(i + offset) ' i ' Get
		
		Local newValue:= (t.lTable.GetUnsigned(length) + 1) ' GetUnsigned
		
		' Increment by one.
		t.lTable.Set(length, newValue)
	Next
	
	' Set the first entry to zero.
	t.lTable.Set(0, 0)
	
	' Compute offset table for distribution sort:
	Local sum:= 0
	
	For Local i:= 0 Until InfTree.LTABLE_LENGTH ' offs.Length ' 16 ' 1 Until offs.Length
		offs.SetUnsigned(i, sum) ' Set
		
		sum += t.lTable.GetUnsigned(i) ' GetUnsigned
	Next
	
	#Rem ' If REGAL_INFLATE_DEBUG_OUTPUT
		Print("BEGIN")
		
		' Debugging related:
		Local length_bytes:= New Int[lengths.Length-offset]
		
		lengths.Data.PeekBytes(offset, length_bytes, 0, length_bytes.Length) ' PeekInts
		
		If (_dbg) Then
			DebugStop()
		Endif
	#End
	
	' Create code -> symbol translation table (Symbols sorted by code):
	For Local i:= 0 Until num
		Local length:= lengths.GetUnsigned(i + offset) ' 27 = index 7 ' Get
		
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
	
	#If REGAL_INFLATE_DEBUG_OUTPUT
		Print("END")
		
		If (_dbg) Then
			DebugStop()
		Endif
	#End
	
	' Manually discard the offset-buffer.
	offs.Data.Discard()
End

' ////// Decode functions \\\\\\

' Given a data stream and a tree, decode a symbol.
Function inf_decode_symbol:Int(d:InfSession, t:InfTree, __dbg:Bool=False)
	Local sum:= 0
	Local cur:= 0
	Local len:= 0
	
	#If REGAL_INFLATE_DEBUG_OUTPUT
		'Print("Decoding symbol...")
	#End
	
	Repeat
		cur = ((2 * cur) + d.GetBit())
		
		len += 1
		
		Local offset:= t.lTable.GetUnsigned(len) ' GetUnsigned
		
		sum += offset
		cur -= offset
	Until (cur < 0)
	
	Local index:= (sum + cur)
	
	Local symbol:= t.transTable.GetUnsigned(index) ' GetUnsigned
	
	#If REGAL_INFLATE_DEBUG_OUTPUT
		If (__dbg) Then
			'DebugStop()
			
			Print("Retrieving symbol from trans[" + index + "] = {" + symbol + "}")
		Endif
	#End
	
	Return symbol
End

' Given a data stream, decode dynamic trees from it.
Function inf_decode_trees:Void(d:InfSession, lt:InfTree, dt:InfTree)
	' Optimization potential; dynamic allocations:
	
	' Allocate a temporary length-buffer.
	Local lengths:= New ByteArrayView(288+32) ' 286 ' IntArrayView ' New Int[288+32] ' (InfTree.TRANSTABLE_LENGTH + (InfTree.LTABLE_LENGTH * 2)) ' Byte[] ' 288+32 (320)
	
	' Set all entries of this buffer to zero.
	#If CONFIG = "debug"
		lengths.Clear()
	#End
	
	Local hlit:Int, hdist:Int, hclen:Int ' UInt, ...
	
	' Get 5-bit HLIT. (257-286)
	hlit = d.ReadBits(5, 257) ' 1
	
	' Get 5-bit HDIST. (1-32)
	hdist = d.ReadBits(5, 1)
	
	' Get 4-bit HCLEN. (4-19)
	hclen = d.ReadBits(4, 4)
	
	#If CONFIG <> "debug"
		lengths.Clear(0, 19) ' clcidx.Length
	#End
	
	' Read code lengths for code length alphabet:
	For Local i:= 0 Until hclen
		' Read 3-bit code lengths. (0-7)
		lengths.Set(clcidx[i], d.ReadBits(3, 0))
	Next
	
	' Build code length tree, temporarily use length tree.
	Local code_tree:= New InfTree() ' lt
	
	inf_build_tree(code_tree, lengths, 19, 0) ' clcidx.Length
	
	' Decode code lengths for the dynamic trees:
	Local num:= 0
	
	Local max_num:= (hlit + hdist)
	
	DebugStop()
	
	While (num < max_num)
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
	
	' Build dynamic treee:
	
	' Build literal lengths.
	inf_build_tree(lt, lengths, hlit, 0, True) ' 1
	
	' Build distance codes.
	inf_build_tree(dt, lengths, hdist, hlit)
	
	' With the trees built, discard our temporary length-buffer.
	'lengths.Data.Discard()
End

' ////// Block inflate functions \\\\\\

' Given a stream and two trees, inflate a block of data.
Function inf_inflate_block_data:Int(context:InfContext, d:InfSession, lt:InfTree, dt:InfTree)
	#If REGAL_INFLATE_DEBUG_OUTPUT
		If (d.destination.Position > 256) Then ' 256 = 255 (Zero added for some reason)
			'DebugStop()
		Endif
		
		DebugStop()
	#End
	
	If (d.curlen = 0) Then
		#If REGAL_INFLATE_DEBUG_OUTPUT
			'Print("// Huffman symbol \\")
		#End
		
		Local sym:= inf_decode_symbol(d, lt, True)
		
		#If REGAL_INFLATE_DEBUG_OUTPUT
			Print("Huffman symbol: " + sym)
		#End
		
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
	d.bFinal = d.GetBit() ' > 0
	
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