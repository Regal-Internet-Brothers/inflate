Strict

' Imports:
Private
	Import regal.sizeof
	
	Import util
Public

' Classes:
Class InfTree
	Private
		' Constant variable(s):
		Const LTABLE_LENGTH:= 16
		Const TRANSTABLE_LENGTH:= 286 ' 288 ' 256+32
	Public
		' Methods:
		Method Get_lTable:Int(index:Int) ' Short
			'Local value:= Get_Short(lTable, index)
			Local value:= lTable.PeekShort(index*SizeOf_Short)
			
			'Print("Get|LTABLE[" + index + "] = " + value)
			
			'Return Get_Short(lTable, index)
			
			Return value
		End
		
		Method Get_transTable:Int(index:Int) ' Short
			'Local value:= Get_Short(transTable, index)
			Local value:= transTable.PeekShort(index*SizeOf_Short)
			
			'Print("Get|TRANSTABLE[" + index + "] = " + value)
			
			'Return Get_Short(transTable, index)
			
			Return value
		End
		
		Method Set_lTable:Void(index:Int, value:Int) ' Short
			'Set_Short(lTable, index, value)
			lTable.PokeShort(index*SizeOf_Short, value)
		End
		
		Method Set_transTable:Void(index:Int, value:Int, _dbg:Bool=False) ' Short
			If (_dbg) Then
				If (index = 20 Or index = 8) Then ' 13 (Custom)
					Print("Setting index "+index+", value: " + value)
					
					'DebugStop()
				Endif
			Endif
			
			'Set_Short(transTable, index, value)
			transTable.PokeShort(index*SizeOf_Short, value)
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