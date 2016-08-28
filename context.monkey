Strict

' Imports:
Import config

Private
	#If Not REGAL_INFLATE_RUNTIME_TABLES
		Import regal.util.memory
	#End
	
	Import util
Public

' Constant variable(s):
Private
	' The type-adjusted lengths of the "bit" and "base" buffers used internally.
	Const BIT_BASE_LENGTH:= 30
Public

' Classes:

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
				SetBufferBytes(length_bits, [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5,  0, 0]) ' 0, 6
				SetBufferShorts(length_base, [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258,  0]) ' 323
				
				' Distances:
				SetBufferBytes(dist_bits, [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13])
				SetBufferShorts(dist_base, [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577])
			#End
		End
End