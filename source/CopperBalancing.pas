{ Copper Balancing v0.2.1. Experimental; native region + manifest ownership.
  Coordinates: Altium integer units (10000/mil). Obstacles conservatively boxed.
  No polygon repour, rules edits, or power-plane edits. Full islands only. }
Const
 CBPrefix = 'CBAL_7F93C2A1_';
 CBHeader = 'CopperBalancing manifest v1';
 CBMax = 30000;
Var
 CBBoard : IPCB_Board;
 CBManifest, CBNames, CBHandles : TStringList;
 CBOld : Array[0..29999] Of IPCB_Region;
 CBNew : Array[0..29999] Of IPCB_Region;
 CBX, CBY, CBLayer : Array[0..29999] Of Integer;
 OBLeft, OBBottom, OBRight, OBTop, OBMargin : Array[0..29999] Of Integer;
 CBLeft, CBBottom, CBRight, CBTop : Integer;
 CBPitch, CBSize, CBSpacing, CBClearance, CBEdge, CBHV, CBOriginX, CBOriginY : Integer;
 CBPattern, CBLayers, CBHVNets : String;
 CBOldCount, CBNewCount, CBPlanCount, OBCount, CBRejected : Integer;
 CBManifestFile : String;
 CBUseSelectedArea : Boolean;
 CBStarted : Integer;
 CBStackCount, CBSelectedCount : Integer;
 CBStackIDs : Array[0..63] Of Integer;
 CBStackNames : Array[0..63] Of String;
 CBPositive, CBSelected : Array[0..63] Of Boolean;

Procedure CBFail(S : String);
Begin Raise(S); End;

Function CBMin(A,B : Integer) : Integer;
Begin If A<B Then Result:=A Else Result:=B; End;
Function CBMaxInt(A,B : Integer) : Integer;
Begin If A>B Then Result:=A Else Result:=B; End;

Function CBSignature(R : IPCB_Region) : String;
Var S : TStringList; I : Integer;
Begin
 S:=TStringList.Create;
 Try
  For I:=1 To R.MainContour.Count Do
   S.Add(IntToStr(R.MainContour.X[I])+','+IntToStr(R.MainContour.Y[I]));
  S.Sort;
  Result:=IntToStr(R.Layer)+'/'+IntToStr(R.Kind)+'/'+IntToStr(R.UnionIndex)+'/'+IntToStr(R.HoleCount)+'/'+S.CommaText;
  If R.Net<>Nil Then Result:=Result+'/NET';
  If R.IsKeepout Then Result:=Result+'/KEEPOUT';
  If R.InPolygon Then Result:=Result+'/POLYGON';
  If R.InComponent Then Result:=Result+'/COMPONENT';
 Finally S.Free; End;
End;

Procedure CBOpen;
Begin
 CBStarted:=GetTickCount;
 CBBoard:=PCBServer.GetCurrentPCBBoard;
 If CBBoard=Nil Then CBFail('Open a saved PCB first.');
 If Not FileExists(CBBoard.FileName) Then CBFail('Save this test PCB before running the tool.');
 { Release gate: expand only after the full native qualification matrix passes. }
 If Pos('copper-balancing-20261122',LowerCase(CBBoard.FileName))=0 Then
  CBFail('Experimental build is restricted to the isolated copper-balancing-20261122 test directory.');
 CBManifestFile:=CBBoard.FileName+'.cbal-manifest';
 CBManifest:=TStringList.Create; CBNames:=TStringList.Create; CBHandles:=TStringList.Create; CBHandles.Sorted:=True;
 CBOldCount:=0; CBNewCount:=0; CBPlanCount:=0; OBCount:=0; CBRejected:=0;
 If FileExists(CBManifestFile) Then Begin
  CBManifest.LoadFromFile(CBManifestFile);
  If (CBManifest.Count=0) Then CBFail('Empty manifest. Refusing ownership inference.');
  If CBManifest[0]<>CBHeader Then CBFail('Unknown manifest format.');
 End Else CBManifest.Add(CBHeader);
End;

Procedure CBClose;
Begin CBManifest.Free; CBNames.Free; CBHandles.Free; End;

Procedure CBCollectOwned;
Var It : IPCB_BoardIterator; R : IPCB_Region; Key : String;
Begin
 It:=CBBoard.BoardIterator_Create;
 Try
 It.AddFilter_ObjectSet(MkSet(eRegionObject)); It.AddFilter_LayerSet(AllLayers); It.AddFilter_Method(eProcessAll);
 R:=It.FirstPCBObject;
 While R<>Nil Do Begin
  If Copy(R.Name,1,Length(CBPrefix))=CBPrefix Then Begin
   Key:=R.Name;
   If CBNames.IndexOf(Key)>=0 Then CBFail('Duplicate owned name: '+Key);
   CBNames.Add(Key); CBHandles.Add(IntToStr(R.I_ObjectAddress));
   If CBManifest.Values[Key]<>CBSignature(R) Then CBFail('Missing or changed ownership fingerprint: '+Key);
   If CBOldCount>=CBMax Then CBFail('Too many owned regions.');
   CBOld[CBOldCount]:=R; Inc(CBOldCount);
  End;
  R:=It.NextPCBObject;
 End;
 Finally CBBoard.BoardIterator_Destroy(It); End;
End;

Function CBIsOwned(P : IPCB_Primitive) : Boolean;
Begin Result:=CBHandles.IndexOf(IntToStr(P.I_ObjectAddress))>=0; End;

Procedure CBStage(S : String);
Var L : TStringList; B : IPCB_Board;
Begin
 { Diagnostics follow only saved isolated task boards; no privileged C: path. }
 B:=PCBServer.GetCurrentPCBBoard; If B=Nil Then Exit;
 If Pos('copper-balancing-20261122',LowerCase(B.FileName))=0 Then Exit;
 If Not FileExists(B.FileName) Then Exit;
 L:=TStringList.Create;
 Try L.Add(S); L.SaveToFile(B.FileName+'.cbal-stage.txt'); Finally L.Free; End;
End;

{ Enumerate only electrical layers actually present in this board stack.
  InternalPlane IDs are negative artwork. They are shown, disabled, never emitted. }
Procedure CBReadCopperLayers;
Var B : IPCB_Board; LS : IPCB_LayerStack; LO : IPCB_LayerObject; ID : Integer;
Begin
 B:=PCBServer.GetCurrentPCBBoard;
 If B=Nil Then CBFail('Open a saved PCB first.');
 LS:=B.LayerStack_V7; If LS=Nil Then CBFail('Cannot read board copper stack.');
 CBStackCount:=0; LO:=LS.FirstLayer;
 While LO<>Nil Do Begin
  If CBStackCount>=64 Then CBFail('Copper stack exceeds supported layer count.');
  ID:=Ord(LO.LayerID);
  CBStackIDs[CBStackCount]:=ID;
  CBStackNames[CBStackCount]:=LO.Name+' ['+Layer2String(LO.LayerID)+']';
  CBPositive[CBStackCount]:=(ID>=Ord(eTopLayer)) And (ID<=Ord(eBottomLayer));
  If Not CBPositive[CBStackCount] Then
   If (ID<Ord(eInternalPlane1)) Or (ID>Ord(eInternalPlane16)) Then
    CBFail('Unknown copper layer type; refusing generation.');
  CBSelected[CBStackCount]:=CBPositive[CBStackCount];
  Inc(CBStackCount); LO:=LS.NextLayer(LO);
 End;
 If CBStackCount=0 Then CBFail('No copper layers in active board stack.');
End;

Procedure CBDescribeSelectedLayers;
Var I : Integer;
Begin
 CBLayers:=''; CBSelectedCount:=0;
 For I:=0 To CBStackCount-1 Do If CBSelected[I] Then Begin
  If Not CBPositive[I] Then CBFail('Negative plane selection refused.');
  If CBLayers<>'' Then CBLayers:=CBLayers+'; ';
  CBLayers:=CBLayers+CBStackNames[I]; Inc(CBSelectedCount);
 End;
 If CBSelectedCount=0 Then CBFail('Select at least one positive copper layer.');
End;

Procedure CBDefaults;
Begin
 CBPitch:=MMsToCoord(3); CBSize:=MMsToCoord(1.5); CBSpacing:=MMsToCoord(1);
 CBClearance:=MMsToCoord(0.5); CBEdge:=MMsToCoord(1); CBHV:=MMsToCoord(6);
 CBOriginX:=0; CBOriginY:=0; CBUseSelectedArea:=False; CBPattern:='Diamond'; CBHVNets:='HV_400V';
 CBReadCopperLayers; CBDescribeSelectedLayers;
End;

Procedure CBOutline;
Var It : IPCB_BoardIterator; P : IPCB_Primitive; F : IPCB_Fill; Seen : Array[0..3] Of Boolean; K : Integer; AreaCount : Integer; I,J : Integer; S,T : TPolySegment; R : TCoordRect;
Begin
 { Conservative first release accepts proven axis-aligned rectangular outlines.
   Curves, concavity and rigid-flex require a separately qualified contour engine. }
 If CBBoard.BoardOutline.PointCount<>4 Then CBFail('Only a four-corner rectangular board outline is qualified in v0.1.');
 R:=CBBoard.BoardOutline.BoundingRectangle;
 CBLeft:=R.Left; CBRight:=R.Right; CBBottom:=R.Bottom; CBTop:=R.Top;
 For I:=0 To 3 Do Seen[I]:=False;
 For I:=0 To 3 Do Begin
  S:=CBBoard.BoardOutline.Segments[I]; J:=(I+1) Mod 4; T:=CBBoard.BoardOutline.Segments[J];
  If S.Kind<>ePolySegmentLine Then CBFail('Curved board outline is unsupported.');
  If (S.vx<>T.vx) And (S.vy<>T.vy) Then CBFail('Nonrectangular board outline is unsupported.');
  If ((S.vx<>CBLeft) And (S.vx<>CBRight)) Or ((S.vy<>CBBottom) And (S.vy<>CBTop)) Then CBFail('Invalid rectangle outline.');
  K:=0; If S.vx=CBRight Then K:=K+1; If S.vy=CBTop Then K:=K+2;
  If Seen[K] Then CBFail('Repeated board-outline corner.'); Seen[K]:=True;
 End;
 If CBUseSelectedArea Then Begin
  AreaCount:=0; It:=CBBoard.BoardIterator_Create;
  Try
   It.AddFilter_ObjectSet(MkSet(eFillObject)); It.AddFilter_LayerSet(MkSet(eMechanical1)); It.AddFilter_Method(eProcessAll);
   P:=It.FirstPCBObject;
   While P<>Nil Do Begin
    If P.Selected Then Begin
     F:=P; If F.Rotation<>0 Then CBFail('Selected area Fill must have zero rotation.');
     Inc(AreaCount); R:=P.BoundingRectangle;
     CBLeft:=CBMaxInt(CBLeft,R.Left); CBRight:=CBMin(CBRight,R.Right);
     CBBottom:=CBMaxInt(CBBottom,R.Bottom); CBTop:=CBMin(CBTop,R.Top);
    End;
    P:=It.NextPCBObject;
   End;
  Finally CBBoard.BoardIterator_Destroy(It); End;
  If AreaCount<>1 Then CBFail('Select exactly one rectangular Fill on Mechanical 1 for area mode.');
 End;
End;

Procedure CBAddObstacle(L,B,R,T,M : Integer);
Begin
 If OBCount>=CBMax Then CBFail('Obstacle limit reached; no PCB changes.');
 OBLeft[OBCount]:=L; OBBottom[OBCount]:=B; OBRight[OBCount]:=R; OBTop[OBCount]:=T; OBMargin[OBCount]:=M; Inc(OBCount);
End;

Procedure CBObstacles;
Var It : IPCB_BoardIterator; P : IPCB_Primitive; R : TCoordRect; M : Integer; N : String; IsObstacle : Boolean; Region : IPCB_Region;
Begin
 It:=CBBoard.BoardIterator_Create;
 Try
 It.AddFilter_ObjectSet(MkSet(ePadObject,eViaObject,eTrackObject,eArcObject,eFillObject,eRegionObject,ePolyObject));
 It.AddFilter_LayerSet(AllLayers); It.AddFilter_Method(eProcessAll);
 P:=It.FirstPCBObject;
 While P<>Nil Do Begin
  { Board stack region has its own ObjectId and is not copper/cutout geometry. }
  IsObstacle:=True;
  If P.ObjectId=eRegionObject Then Begin Region:=P; IsObstacle:=Region.IsSimpleRegion; End;
  If IsObstacle And Not CBIsOwned(P) Then
  If (P.ObjectId=ePadObject) Or (P.ObjectId=eViaObject) Or (P.ObjectId=eTrackObject) Or (P.ObjectId=eArcObject) Or (P.ObjectId=eFillObject) Or (P.ObjectId=eRegionObject) Or (P.ObjectId=ePolyObject) Then Begin
   If ((P.Layer>=eTopLayer) And (P.Layer<=eBottomLayer)) Or P.IsKeepout Or (P.Layer=eMultiLayer) Or (P.Layer=eKeepOutLayer) Then Begin
    R:=P.BoundingRectangle; M:=CBClearance;
    If P.ObjectId=eRegionObject Then Begin Region:=P; If Region.Kind<>eRegionKind_Copper Then M:=CBMaxInt(M,CBEdge); End;
    If (P.Layer=eKeepOutLayer) Or P.IsKeepout Then M:=CBMaxInt(M,CBEdge);
    If P.Net<>Nil Then Begin
     N:=P.Net.Name;
     If Pos(','+UpperCase(N)+',',','+UpperCase(CBHVNets)+',')>0 Then M:=CBMaxInt(M,CBHV);
    End;
    CBAddObstacle(R.Left,R.Bottom,R.Right,R.Top,M+1);
   End;
  End;
  P:=It.NextPCBObject;
 End;
 Finally CBBoard.BoardIterator_Destroy(It); End;
End;

Function CBCandidate(X,Y : Integer) : Boolean;
Var I,H,M : Integer;
Begin
 Result:=False; H:=(CBSize+1) Div 2;
 If (X-H<CBLeft+CBEdge+1) Or (X+H>CBRight-CBEdge-1) Or
    (Y-H<CBBottom+CBEdge+1) Or (Y+H>CBTop-CBEdge-1) Then Exit;
 For I:=0 To OBCount-1 Do Begin
  M:=OBMargin[I];
  If (X+H>=OBLeft[I]-1.0*M) And (X-H<=OBRight[I]+1.0*M) And (Y+H>=OBBottom[I]-1.0*M) And (Y-H<=OBTop[I]+1.0*M) Then Exit;
 End;
 Result:=True;
End;

Procedure CBPlan;
Var X,Y,L : Integer;
Begin
 If (CBSize<MMsToCoord(0.2)) Or (CBSize>MMsToCoord(100)) Then CBFail('Island dimension must be 0.2..100 mm.');
 If (CBPitch<CBSize+CBSpacing) Or (CBSpacing<MMsToCoord(0.1)) Then CBFail('Pitch must be at least size + spacing; spacing >= 0.1 mm.');
 If (CBClearance<MMsToCoord(0.1)) Or (CBEdge<MMsToCoord(0.1)) Or (CBHV<CBClearance) Then CBFail('Invalid clearance, edge or HV distance.');
 If (Abs(CBOriginX)>MMsToCoord(2000)) Or (Abs(CBOriginY)>MMsToCoord(2000)) Then CBFail('Origin outside supported range.');
 If (CBLeft < -MMsToCoord(2000)) Or (CBRight > MMsToCoord(2000)) Or (CBBottom < -MMsToCoord(2000)) Or (CBTop > MMsToCoord(2000)) Then CBFail('Board coordinate range exceeds +/-2000 mm.');
 If (CBRight<=CBLeft) Or (CBTop<=CBBottom) Then CBFail('Empty generation area.');
 CBDescribeSelectedLayers;
 If ((CBRight-CBLeft)/CBPitch+2)*((CBTop-CBBottom)/CBPitch+2)*CBSelectedCount>60000 Then CBFail('Grid exceeds 60000 candidate budget. Increase pitch or select a smaller area.');
 If (CBRight-CBLeft>MMsToCoord(1000)) Or (CBTop-CBBottom>MMsToCoord(1000)) Then CBFail('Board larger than 1000 mm.');
 For L:=0 To CBStackCount-1 Do If CBSelected[L] Then Begin
  X:=CBOriginX+Ceil((CBLeft-CBOriginX)/CBPitch)*CBPitch;
  While X<=CBRight Do Begin
   Y:=CBOriginY+Ceil((CBBottom-CBOriginY)/CBPitch)*CBPitch;
   While Y<=CBTop Do Begin
    If CBCandidate(X,Y) Then Begin
     If CBPlanCount>=CBMax Then CBFail('Island limit 30000 exceeded; no PCB changes.');
     CBX[CBPlanCount]:=X; CBY[CBPlanCount]:=Y;
     CBLayer[CBPlanCount]:=CBStackIDs[L];
     Inc(CBPlanCount);
    End Else Inc(CBRejected);
    Y:=Y+CBPitch;
   End;
   X:=X+CBPitch;
  End;
 End;
End;

Function CBMakeRegion(X,Y,L : Integer; Name : String) : IPCB_Region;
Var R : IPCB_Region; C : IPCB_Contour; H,Q : Integer;
Begin
 R:=PCBServer.PCBObjectFactory(eRegionObject,eNoDimension,eCreate_Default);
 R.Layer:=L; R.Kind:=eRegionKind_Copper; R.Name:=Name; R.Net:=Nil; R.UnionIndex:=0;
 C:=R.MainContour.Replicate; H:=CBSize Div 2;
 If CBPattern='Hexagon' Then Begin
  C.Count:=6; Q:=Round(H*0.8660254037844386);
  C.X[1]:=X-H; C.Y[1]:=Y; C.X[2]:=X-H Div 2; C.Y[2]:=Y-Q;
  C.X[3]:=X+H Div 2; C.Y[3]:=Y-Q; C.X[4]:=X+H; C.Y[4]:=Y;
  C.X[5]:=X+H Div 2; C.Y[5]:=Y+Q; C.X[6]:=X-H Div 2; C.Y[6]:=Y+Q;
 End Else Begin
  C.Count:=4;
  If CBPattern='Square' Then Begin
   C.X[1]:=X-H; C.Y[1]:=Y-H; C.X[2]:=X+H; C.Y[2]:=Y-H;
   C.X[3]:=X+H; C.Y[3]:=Y+H; C.X[4]:=X-H; C.Y[4]:=Y+H;
  End Else Begin
   C.X[1]:=X-H; C.Y[1]:=Y; C.X[2]:=X; C.Y[2]:=Y-H;
   C.X[3]:=X+H; C.Y[3]:=Y; C.X[4]:=X; C.Y[4]:=Y+H;
  End;
 End;
 R.SetOutlineContour(C); Result:=R;
End;

Procedure CBCommit(Regenerate : Boolean);
Var I : Integer; R : IPCB_Region; Token,Name : String;
Begin
 If (CBOldCount>0) And Not Regenerate Then CBFail('Balancing already exists. Use Regenerate.');
 Token:=IntToStr(GetTickCount);
 { Append-only ownership journal includes retired generations for Undo recovery.
   Journal is written before PCB mutation, so partial failures remain identifiable. }
 For I:=0 To CBPlanCount-1 Do Begin
  Name:=CBPrefix+Token+'_'+IntToStr(CBLayer[I])+'_'+IntToStr(I);
  R:=CBMakeRegion(CBX[I],CBY[I],CBLayer[I],Name);
  CBNew[I]:=R; Inc(CBNewCount); CBManifest.Values[Name]:=CBSignature(R);
 End;
 CBManifest.SaveToFile(CBManifestFile+'.pending');
 
 CBManifest.SaveToFile(CBManifestFile);
 PCBServer.PreProcess;
 Try
  For I:=0 To CBNewCount-1 Do Begin
   CBBoard.AddPCBObject(CBNew[I]);
   PCBServer.SendMessageToRobots(CBBoard.I_ObjectAddress,c_Broadcast,PCBM_BoardRegisteration,CBNew[I].I_ObjectAddress);
  End;
  For I:=0 To CBOldCount-1 Do Begin
   CBBoard.RemovePCBObject(CBOld[I]);
   PCBServer.SendMessageToRobots(CBBoard.I_ObjectAddress,c_Broadcast,PCBM_BoardRegisteration,CBOld[I].I_ObjectAddress);
  End;
 Finally PCBServer.PostProcess; CBBoard.ViewManager_FullUpdate; End;
End;

Procedure CBReport(Action : String);
Var S : TStringList;
Begin
 S:=TStringList.Create;
 Try
 S.Add('Action='+Action); S.Add('Board='+CBBoard.FileName);
 S.Add('SelectedLayers='+CBLayers); S.Add('SelectedLayerCount='+IntToStr(CBSelectedCount));
 S.Add('Planned='+IntToStr(CBPlanCount)); S.Add('Rejected='+IntToStr(CBRejected));
 S.Add('Obstacles='+IntToStr(OBCount)); S.Add('OwnedBefore='+IntToStr(CBOldCount));
 S.Add('Elapsed_ms='+IntToStr(GetTickCount-CBStarted)); S.Add('FullIslandsOnly=true'); S.Add('HV nets='+CBHVNets); S.Add('HV distance coords='+IntToStr(CBHV));
 S.Add('HV insulation qualification=NOT VERIFIED');
 S.SaveToFile(CBBoard.FileName+'.cbal-last-run.txt');
 Finally S.Free; End;
End;

Procedure CBExecute(Action : String);
Var I : Integer;
Begin
 CBStage('open '+Action); CBOpen;
 Try
 CBStage('collect'); CBCollectOwned; CBStage('collected '+IntToStr(CBOldCount));
 If Action='Remove' Then Begin
  PCBServer.PreProcess;
  Try For I:=0 To CBOldCount-1 Do Begin
   CBBoard.RemovePCBObject(CBOld[I]);
   PCBServer.SendMessageToRobots(CBBoard.I_ObjectAddress,c_Broadcast,PCBM_BoardRegisteration,CBOld[I].I_ObjectAddress);
  End;
  Finally PCBServer.PostProcess; End;
  CBBoard.ViewManager_FullUpdate;
 End Else Begin
  CBStage('outline'); CBOutline; CBStage('obstacles'); CBObstacles; CBStage('plan obstacles='+IntToStr(OBCount)+' owned='+IntToStr(CBOldCount)); CBPlan; CBStage('planned '+IntToStr(CBPlanCount));
  If Action<>'DryRun' Then CBCommit(Action='Regenerate');
 End;
 CBReport(Action); CBStage('done '+Action);
 Finally CBClose; End;
End;

Procedure CBLabel(F : TForm; S : String; Y : Integer);
Var L : TLabel;
Begin L:=TLabel.Create(F); L.Parent:=F; L.Left:=16; L.Top:=Y; L.Caption:=S; End;
Function CBEdit(F : TForm; S : String; Y : Integer) : TEdit;
Begin Result:=TEdit.Create(F); Result.Parent:=F; Result.Left:=275; Result.Top:=Y-3; Result.Width:=220; Result.Text:=S; End;

Function CBParseMM(S : String) : Integer;
Var I,D,Digits,Sign : Integer; V,Scale : Double; Decimal : Boolean;
Begin
 S:=Trim(S); If S='' Then CBFail('Empty dimension.');
 V:=0; Scale:=1; Decimal:=False; Digits:=0; Sign:=1; I:=1;
 If S[1]='-' Then Begin Sign:=-1; I:=2; End;
 While I<=Length(S) Do Begin
  If (S[I]='.') Or (S[I]=',') Then Begin
   If Decimal Then CBFail('Use one decimal separator: '+S);
   Decimal:=True;
  End Else Begin
   D:=Ord(S[I])-Ord('0'); If (D<0) Or (D>9) Then CBFail('Invalid dimension: '+S);
   If Decimal Then Begin Scale:=Scale*10; If Scale>1000000 Then CBFail('At most six decimal places.'); V:=V+D/Scale; End
   Else V:=V*10+D;
   Inc(Digits); If V>2000 Then CBFail('Dimension exceeds 2000 mm.');
  End;
  Inc(I);
 End;
 If Digits=0 Then CBFail('Invalid dimension: '+S);
 Result:=MMsToCoord(Sign*V);
End;

Procedure CBDialog(Action : String);
Var F : TForm; Pattern : TComboBox; Pitch,Size,Spacing,Clearance,Edge,HV,HVNets,OriginX,OriginY : TEdit;
 Dry,Go,Cancel : TButton; Area : TCheckBox; LayerChecks : Array[0..63] Of TCheckBox; MR,I,Col,Row : Integer;
Begin
 CBDefaults;
 F:=TForm.Create(Nil);
 Try
 F.Caption:='Copper Balancing - experimental v0.2.1'; F.Width:=1110; F.Height:=730; F.Position:=poScreenCenter; F.BorderStyle:=bsDialog;
 CBLabel(F,'Select copper layers on the right.',20);
 For I:=0 To CBStackCount-1 Do Begin
  Col:=I Div 32; Row:=I Mod 32;
  LayerChecks[I]:=TCheckBox.Create(F); LayerChecks[I].Parent:=F;
  LayerChecks[I].Left:=550+Col*270; LayerChecks[I].Top:=18+Row*19;
  LayerChecks[I].Width:=265; LayerChecks[I].Height:=18;
  LayerChecks[I].Caption:=CBStackNames[I];
  If Not CBPositive[I] Then LayerChecks[I].Caption:=LayerChecks[I].Caption+' (negative)';
  LayerChecks[I].Enabled:=CBPositive[I]; LayerChecks[I].Checked:=CBSelected[I];
 End;
 CBLabel(F,'Pattern',54); Pattern:=TComboBox.Create(F); Pattern.Parent:=F; Pattern.Left:=275; Pattern.Top:=50; Pattern.Width:=220;
 Pattern.Items.Add('Diamond'); Pattern.Items.Add('Square'); Pattern.Items.Add('Hexagon'); Pattern.ItemIndex:=0; Pattern.Style:=csDropDownList;
 CBLabel(F,'Pitch mm',88); Pitch:=CBEdit(F,'3',88);
 CBLabel(F,'Island bounding dimension mm',122); Size:=CBEdit(F,'1.5',122);
 CBLabel(F,'Minimum island spacing mm',156); Spacing:=CBEdit(F,'1',156);
 CBLabel(F,'Copper clearance mm',190); Clearance:=CBEdit(F,'0.5',190);
 CBLabel(F,'Edge / cutout clearance mm',224); Edge:=CBEdit(F,'1',224);
 CBLabel(F,'HV exclusion distance mm',258); HV:=CBEdit(F,'6',258);
 CBLabel(F,'HV net names (comma-separated)',292); HVNets:=CBEdit(F,'HV_400V',292);
 CBLabel(F,'Grid origin X mm',326); OriginX:=CBEdit(F,'0',326);
 CBLabel(F,'Grid origin Y mm',360); OriginY:=CBEdit(F,'0',360);
 Area:=TCheckBox.Create(F); Area.Parent:=F; Area.Left:=16; Area.Top:=390; Area.Width:=510; Area.Caption:='Use selected Mechanical 1 rectangular Fill as area';
 CBLabel(F,'Full islands only. Rectangular boards. All-layer obstacle boxes.',424);
 CBLabel(F,'All positive copper layers selected by default. Negative planes excluded.',466);
 CBLabel(F,'HV distance requires an independent insulation assessment.',445);
 Dry:=TButton.Create(F); Dry.Parent:=F; Dry.Left:=16; Dry.Top:=650; Dry.Caption:='Dry run'; Dry.ModalResult:=7;
 Go:=TButton.Create(F); Go.Parent:=F; Go.Left:=180; Go.Top:=650; Go.Width:=140; Go.Caption:=Action; Go.ModalResult:=1;
 Cancel:=TButton.Create(F); Cancel.Parent:=F; Cancel.Left:=380; Cancel.Top:=650; Cancel.Caption:='Cancel'; Cancel.ModalResult:=2;
 MR:=F.ShowModal; If (MR<>1) And (MR<>7) Then Exit;
 CBPitch:=CBParseMM(Pitch.Text); CBSize:=CBParseMM(Size.Text); CBSpacing:=CBParseMM(Spacing.Text);
 CBClearance:=CBParseMM(Clearance.Text); CBEdge:=CBParseMM(Edge.Text); CBHV:=CBParseMM(HV.Text);
 CBOriginX:=CBParseMM(OriginX.Text); CBOriginY:=CBParseMM(OriginY.Text);
 CBUseSelectedArea:=Area.Checked; CBPattern:=Pattern.Text; CBHVNets:=HVNets.Text;
 For I:=0 To CBStackCount-1 Do CBSelected[I]:=CBPositive[I] And LayerChecks[I].Checked;
 CBDescribeSelectedLayers;
 If MR=7 Then CBExecute('DryRun') Else CBExecute(Action);
 ShowMessage('Planned '+IntToStr(CBPlanCount)+' islands; rejected '+IntToStr(CBRejected)+'. Report saved next to PCB.');
 Finally F.Free; End;
End;

Procedure Generate;
Begin Try CBDialog('Generate'); Except ShowMessage(ExceptionMessage); End; End;
Procedure Regenerate;
Begin Try CBDialog('Regenerate'); Except ShowMessage(ExceptionMessage); End; End;
Procedure Remove;
Begin Try CBDefaults; CBExecute('Remove'); ShowMessage('Removed '+IntToStr(CBOldCount)+' verified owned regions.'); Except ShowMessage(ExceptionMessage); End; End;
Procedure DryRun;
Begin CBDefaults; CBExecute('DryRun'); End;
Procedure TestGenerate;
Begin CBDefaults; CBExecute('Generate'); End;
Procedure TestRegenerate;
Begin Try CBDefaults; CBExecute('Regenerate'); Except CBStage('ERROR '+ExceptionMessage); ShowMessage(ExceptionMessage); End; End;

Procedure TestSquare;
Begin CBDefaults; CBPattern:='Square'; CBExecute('Regenerate'); End;
Procedure TestHexagon;
Begin CBDefaults; CBPattern:='Hexagon'; CBExecute('Regenerate'); End;
