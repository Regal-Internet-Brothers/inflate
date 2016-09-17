Strict

' Imports:
Private
	Import regal.sizeof
	
	Import util
Public

' Classes:
Class InfTree
	Public
		' Constant variable(s):
		Const LTABLE_LENGTH:= 16
		Const TRANSTABLE_LENGTH:= 288 ' 286 ' 288 ' 256+32
		
		' Fields:
		Field lTable:= New IntArrayView(LTABLE_LENGTH) ' ShortArrayView ' Short[]
		Field transTable:= New IntArrayView(TRANSTABLE_LENGTH) ' ShortArrayView ' Short[]
End