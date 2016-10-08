Strict

' Imports:
Private
	Import util
Public

' Aliases:
Alias InfTreeType = Int

' Classes:
Class InfTree
	Public
		' Constant variable(s):
		Const TYPE_LITERAL:InfTreeType		= 0
		Const TYPE_DISTANCE:InfTreeType		= 1
		Const TYPE_CODE:InfTreeType			= 2
		
		' Constructor(s):
		Method New(type:InfTreeType, clearTables:Bool=False)
			Self.type = type
			
			Select (type)
				Case TYPE_LITERAL
					Self.lTable = New ByteArrayView(288) ' 16
					Self.transTable = New ShortArrayView(288*2-2) ' 288 (2 Reserved; 286 dynamic, 288 static)
				Case TYPE_DISTANCE
					Self.lTable = New ByteArrayView(32)
					Self.transTable = New ShortArrayView(32*2-2) ' 34 (2 Reserved)
				Case TYPE_CODE
					Self.lTable = New ByteArrayView(19)
					Self.transTable = New ShortArrayView(19*2-2) ' 21 (2 Reserved)
			End Select
			
			#If CONFIG = "debug"
				clearTables = True
			#End
			
			'If (clearTables) Then
			lTable.Clear()
			transTable.Clear()
			'Endif
		End
		
		' Fields:
		Field type:InfTreeType
		
		' Table lengths.
		Field lTable:ByteArrayView ' Short[]
		
		' Table translations.
		Field transTable:ShortArrayView ' Short[]
End