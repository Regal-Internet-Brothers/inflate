Strict

' Imports:
Private
	Import util
Public

' Classes:
Class InfTree
	Public
		' Constant variable(s):
		Const LTABLE_LENGTH:= 16
		Const TRANSTABLE_LENGTH:= 288 ' 286 ' 288 ' 256+32
		
		' Fields:
		Field lTable:= New ShortArrayView(LTABLE_LENGTH) ' IntArrayView ' Short[]
		Field transTable:= New ShortArrayView(TRANSTABLE_LENGTH) ' IntArrayView ' Short[]
End