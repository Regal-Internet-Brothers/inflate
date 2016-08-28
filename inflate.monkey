Strict

' A Monkey port of 'Tiny Inflate' by Joergen Ibsen.

' Imports:
Import config

Private
Import util
Import tree
Import impl

Public
Import meta
Import session
Import context

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
			'DebugStop()
			
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

' This implementation is currently untested and may be unsafe.
Function InfParseGZipHeader:Int(d:InfSession)
	' Constant variable(s):
	
	' Header flag-masks:
	Const FTEXT:=		1
	Const FHCRC:=		2
	Const FEXTRA:=		4
	Const FNAME:=		8
	Const FCOMMENT:=	16
	
	' -- Check format -- '
	
	' Check the ID bytes:
	If (d.ReadByte() <> $1F Or d.ReadByte() <> $8B) Then
		Return INF_DATA_ERROR
	Endif
	
	' Ensure the method used is deflate.
	If (d.ReadByte() <> 8) Then
		Return INF_DATA_ERROR
	Endif
	
	' Get the flag-byte.
	Local flg:= d.ReadByte()
	
	' Check that reserved bits are zero.
	If ((flg & $E0)) Then
		Return INF_DATA_ERROR
	Endif
	
	' -- Find the start of the compressed data stream -- '
	
	' Skip the rest of the base-header (10 bytes total; 6 remaining).
	d.SeekForward(6)
	
	' Skip extra data, if present:
	If ((flg & FEXTRA)) Then
		Local xlen:= d.ReadShort()
		
		d.SeekForward(xlen)
	Endif
	
	' Skip the file-name, if present:
	If ((flg & FNAME)) Then
		' Skip the characters of the name by waiting for a null-character.
		While (d.ReadByte() <> 0); Wend
	Endif
	
	' Skip the file-comment, if present:
	If ((flg & FCOMMENT)) Then
		' Skip the characters of the comment as we
		' did for the name; wait for a null-character.
		While (d.ReadByte() <> 0); Wend
	Endif
	
	' Check if the header says a CRC is present.
	If ((flg & FHCRC)) Then
		' This is currently ignored; a proper
		' legitimacy-check may be added at a later date.
		Local hcrc:= d.ReadShort()
	Endif
	
	' Initialize the CRC32 checksum:
	d.checksum_type = INF_CHECKSUM_CRC32
	d.checksum = ~0
	
	Return INF_OK
End