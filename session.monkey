Strict

' Friends:
Friend regal.inflate
Friend regal.inflate.impl

' Imports:
Import config

Private
	#If REGAL_INFLATE_IOUTIL ' REGAL_INFLATE_IOUTIL_PBS_EXT
		Import regal.ioutil.publicdatastream
		'Import regal.ioutil.repeater
	#End
	
	Import util
	Import tree
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
		
		' This seeks forward in the source-stream
		' by the number of bytes specified.
		Method SeekForward:Int(amount:Int)
			Return SeekForward(amount)
		End
		
		' Input wrappers:
		Method ReadInt:Int()
			Return (source.ReadInt() & $FFFFFFFF)
		End
		
		Method ReadShort:Int()
			Return (source.ReadShort() & $FFFF)
		End
		
		Method ReadByte:Int()
			Return (source.ReadByte() & $FF)
		End
		
		' Output wrappers:
		
		' This directly writes a byte to the 'destination' stream.
		Method WriteByte:Int(value:Int)
			Local out_value:= (value & $FF)
			
			destination.WriteByte(out_value)
			
			Return out_value
		End
		
		' This writes a byte to the 'destination', and
		' stores that value in an internal ring-buffer, if available.
		Method Put:Void(value:Int)
			#If REGAL_INFLATE_DEBUG_OUTPUT
				Print("PUT: " + value + "   {Dest: " + destination.Position + ", Src: " + source.Position + "}")
				
				'If (destination.Position = 1) Then
				If (value = 0) Then
					DebugStop()
				Endif
				
				'DebugStop()
			#End
			
			value = WriteByte(value)
			
			If (dict_ring) Then ' <> Null
				Set_Byte(dict_ring, dict_idx, value)
				
				dict_idx += 1
				
				If (dict_idx = dict_size) Then ' >=
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
		
		' Testing-related:
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