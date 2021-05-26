unit water;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, Spin,
  ExtCtrls;

type


  { TForm1 }

  TForm1 = class(TForm)
    BSolve: TButton;
    BUndo: TButton;
    CBSingle: TCheckBox;
    Panel1: TPanel;
    TBRandom: TButton;
    Label1: TLabel;
    Label2: TLabel;
    Label3: TLabel;
    Memo1: TMemo;
    NColorsSpin: TSpinEdit;
    NFreeVialSpin: TSpinEdit;
    NVolumeSpin: TSpinEdit;
    procedure BSolveClick(Sender: TObject);
    procedure BUndoClick(Sender: TObject);
    procedure CBSingleChange(Sender: TObject);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FormCreate(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
    procedure FormKeyUp(Sender: TObject; var Key: word; Shift: TShiftState);
    procedure NColorsSpinChange(Sender: TObject);
    procedure NFreeVialSpinChange(Sender: TObject);
    procedure NVolumeSpinChange(Sender: TObject);
    procedure Panel1MouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: integer);
    procedure Panel1Paint(Sender: TObject);
    procedure TBRandomClick(Sender: TObject);
  private

  public

  end;

  TCls = (EMPTY, BLUE, RED, LIME, YELLOW, FUCHSIA, AQUA, GRAY, ROSE, OLIVE,
    BROWN, LBROWN, GREEN, LBLUE, BLACK);
  TState = array of array of TList;
  THash = array of array of array of UInt32;
  TVialsDef = array of array of TCls;
  TColDef = array of TColor;

  //cols: array of TColor = (clWhite, clBlue, clRed, clLime, clYellow, clFuchsia, clAqua,
  //   clSkyBlue, clGreen, clOlive, clTeal, clNavy, TColor($2A2AA5),
  TVialTopInfo = record
    empty: integer; //empty volume of vial
    topcol: integer;//surface color, 0 for empty vial
    topvol: integer;//volume of surface color, NVOLUME for empty vial
  end;

  TMoveInfo = record
    srcVial: UInt8; //source and destination of a move
    dstVial: UInt8;
    merged: boolean;//move reduced number of blocks or keeps number
  end;

  { TVial }

  TVial = class
  public
    color: array of TCls;//colors starting from top of vial
    pos: UInt8; //Index of vial
    constructor Create(var c: array of TCls; p: UInt8);
    destructor Destroy; override;
    function getTopInfo: TVialTopInfo;
    function vialBlocks: integer;
  end;

  { TNode }

  TNode = class
  public
    vial: array of TVial;
    hash: UInt32;
    mvInfo: TMoveInfo;
    constructor Create(t: TVialsDef);
    constructor Create(node: TNode);
    destructor Destroy; override;
    procedure printRaw(w: TMemo);
    procedure print(w: TMemo);
    function getHash: UInt32;
    procedure writeHashbit;
    function isHashedQ: boolean;
    function nodeBlocks: integer;
    function equalQ(node: TNode): boolean;
    function lastmoves: string;
    function Nlastmoves(singlemode: boolean): integer;
  end;



const
  cols: array of TColor = (clWhite, clBlue, clRed, clLime, clYellow, clFuchsia, clAqua,
    clGray, TColor($8c5eeb), clOlive, TColor($2d6cc1), TColor($7aacff), TColor($1a6201),
    TColor($FF8C00), clBlack);
  XOFF = 10;
  YOFF = 20;

var
  Form1: TForm1;
  NCOLORS, NVIALS, NEMPTYVIALS, NVOLUME, NEXTRA: integer;
  hashbits: array of UInt64;
  vialsDefHist: array [0..1000] of TVialsDef;
  undoHist: integer;
  stop: boolean;// abort optimal solving
  shifted: boolean;// shift state
  singleMode: boolean;//Single Block Mode  or Multi Block Mode

implementation

uses Math;

{$R *.lfm}

var
  state: TState;
  hsh: THash;
  globVialdef: TVialsDef;
  srcVial, dstVial, srcblock, dstblock: integer;

function compare(v1, v2: TVial): integer;
var
  i: integer;
begin
  for i := 0 to NVOLUME - 1 do
  begin
    if v1.color[i] < v2.color[i] then
      exit(1);
    if v1.color[i] > v2.color[i] then
      exit(-1);
  end;
  Result := 0;
end;

procedure sortNode(var node: TNode; iLo, iHi: integer);
var
  Lo, Hi: integer;
  Pivot, T: TVial;
begin
  Lo := iLo;
  Hi := iHi;
  Pivot := node.vial[(Lo + Hi) div 2];
  repeat
    while compare(node.vial[Lo], Pivot) = 1 do
      Inc(Lo);
    while compare(node.vial[Hi], Pivot) = -1 do
      Dec(Hi);
    if Lo <= Hi then
    begin
      T := node.vial[Lo];
      node.vial[Lo] := node.vial[Hi];
      node.vial[Hi] := T;
      Inc(Lo);
      Dec(Hi);
    end;
  until Lo > Hi;
  if Hi > iLo then
    sortNode(node, iLo, Hi);
  if Lo < iHi then
    sortNode(node, Lo, iHi);
end;


procedure init(global: boolean = True);
var
  i, j, k: integer;
begin

  NCOLORS := Form1.NColorsSpin.Value;
  NEMPTYVIALS := Form1.NFreeVialSpin.Value;
  NVOLUME := Form1.NVolumeSpin.Value;
  NVIALS := NCOLORS + NEMPTYVIALS;

  if singleMode then //only a single block per move
    NEXTRA := 60//Should be enough for NCOLORS<=12 and NVOLUME<=6
  else
    NEXTRA := NCOLORS + 3;//Should be enough for all configurations


  Randomize;
  SetLength(state, 0, 0);
  SetLength(state, NCOLORS * (NVOLUME - 1) + 1, NEXTRA + 1);
  SetLength(hsh, 0, 0, 0);
  SetLength(hsh, NCOLORS + 1, NVOLUME, NVIALS);
  for i := 0 to NCOLORS do
    for j := 0 to NVOLUME - 1 do
      for k := 0 to NVIALS - 1 do
        hsh[i, j, k] := Random(4294967295); //color, position, vial
  SetLength(hashbits, 67108864);
  for i := 0 to 67108864 - 1 do
    hashbits[i] := 0;

  if global then
  begin
    SetLength(globVialdef, NVIALS, NVOLUME);
    for i := 0 to NCOLORS - 1 do
      for j := 0 to NVOLUME - 1 do
        globVialdef[i, j] := TCls(i + 1);
    for i := NCOLORS to NVIALS - 1 do
      for j := 0 to NVOLUME - 1 do
        globVialdef[i, j] := EMPTY;
    undoHist := -1;
    Form1.Caption := 'ColorSortOptimalSolver';
    Form1.Panel1.Invalidate;
  end;

  srcVial := -1;
  dstVial := -1;
  srcblock := -1;
  dstblock := -1;
  //shifted:=false;
end;

function retrieveOptimalSolution(nblock: integer): string;
var
  i, j, k, kcand, x, y, src, dst, ks, kd, vmin, solLength, addmove: integer;
  nd, ndcand: TNode;
  ndlist: TList;
  viS, viD: TVialTopInfo;
  resback, ms, ft, mv2: string;
  A: TStringArray;
label
  freemem;
begin
  if stop then
  begin
    Result := 'Computation aborted!';
  end;


  Result := '';
  if NVIALS > 9 then
    ft := '%2d->%2d,'
  else
    ft := '%d->%d,';
  if nblock = NCOLORS then
  begin
    //Result := 'Puzzle almost solved!';
    Result := TNode(state[0, 0][0]).lastmoves;
    goto freemem;
  end;


  //search the best solution

  ndcand := nil;
  for i := 0 to NEXTRA do
  begin
    for j := 0 to state[nblock - NCOLORS, i].Count - 1 do
      if ndcand = nil then
      begin
        ndcand := TNode(state[nblock - NCOLORS, i][j]);
        kcand := i + ndcand.Nlastmoves(singleMode);//measure for solution length
        y := i;
        break;
      end;
  end;


  if ndcand = nil then
  begin
    if not stop then
      Result := 'No solution. Undo moves or create new puzzle.'
    else
      Result := 'Computation aborted!';
    goto freemem;
  end;

  for i := 0 to NEXTRA do
  begin
    for j := 0 to state[nblock - NCOLORS, i].Count - 1 do
    begin
      nd := TNode(state[nblock - NCOLORS, i][j]);
      k := i + nd.Nlastmoves(singleMode);
      if k < kcand then
      begin
        kcand := k;
        ndcand := nd;
        y := i;
      end;
    end;
  end;

  //Form1.Memo1.Lines.Add(Inttostr(y)+'   3');
  //Form1.Memo1.Lines.Add(Inttostr(ndcand.Nlastmoves(singleMode)));
  //ndcand.printRaw(Form1.Memo1);


  nd := ndcand;
  addMove := nd.Nlastmoves(singleMode); //add last two moves seperate
  mv2 := nd.lastmoves;
  x := nblock - NCOLORS;

  src := nd.mvInfo.srcVial;
  dst := nd.mvInfo.dstVial;
  Result := Result + Format(ft, [src + 1, dst + 1]);
  if nd.mvInfo.merged then
  begin
    Dec(x);
  end
  else
  begin
    Dec(y);
  end;

  solLength := 1;
  while (x <> 0) or (y <> 0) do
  begin
    ndlist := state[x, y];
    for i := 0 to ndlist.Count - 1 do
    begin
      ndcand := TNode.Create(TNode(ndlist.Items[i]));

      ks := 0;
      while ndcand.vial[ks].pos <> src do
        Inc(ks);
      kd := 0;
      while ndcand.vial[kd].pos <> dst do
        Inc(kd);

      viS := ndcand.vial[ks].getTopInfo;
      viD := ndcand.vial[kd].getTopInfo;
      if viS.empty = NVOLUME then
      begin
        ndcand.Free;
        continue;//source is empty vial
      end;

      if not singleMode then
      begin
        if (viD.empty = 0)(*destination vial full*) or
          ((viD.empty < NVOLUME) and (viS.topcol <> viD.topcol))
          (*destination not empty and top colors different*) or
          ((viD.empty = NVOLUME) and (viS.topvol + viS.empty = NVOLUME))
        (*destinaion empty and only one color in source*) then
        begin
          ndcand.Free;
          continue;
        end;
        vmin := Min(viD.empty, viS.topvol);
        for j := 1 to vmin do
        begin
          ndcand.vial[kd].color[viD.empty - j] := TCls(viS.topcol);
          ndcand.vial[ks].color[vis.empty - 1 + j] := EMPTY;
        end;
      end
      else
      begin
        if (viD.empty = 0)(*destination vial full*) or
          ((viD.empty < NVOLUME) and (viS.topcol <> viD.topcol))
          (*destination not empty and top colors different*) or
          ((viD.empty = NVOLUME) and (viS.topvol = 1) and
          (viS.empty = NVOLUME - 1))
        (*destinaion empty and only one ball in source*) then
        begin
          ndcand.Free;
          continue;
        end;
        ndcand.vial[kd].color[viD.empty - 1] := TCls(viS.topcol);
        ndcand.vial[ks].color[viS.empty] := EMPTY;
      end;

      sortNode(ndcand, 0, NVIALS - 1);
      if nd.equalQ(ndcand) then
      begin
        ndcand.Free;
        nd := TNode(ndlist.Items[i]);
        src := nd.mvInfo.srcVial;
        dst := nd.mvInfo.dstVial;
        Result := Result + Format(ft, [src + 1, dst + 1]);
        Inc(solLength);
        //if solLength mod 10 = 0 then
        //  Result := Result + sLineBreak;
        if nd.mvInfo.merged then
          Dec(x)
        else
          Dec(y);
        break;
      end;
      ndcand.Free;
    end;//i;
  end;


  Form1.Memo1.Lines.Add(Format('Optimal solution in %d moves.', [solLength + addMove]));


  A := Result.Split(','); //Reverse move string
  k := Length(A);
  resback := '';
  for i := k - 1 downto 0 do
  begin
    resback := resback + A[i] + '  ';
    if (k - i - 1) mod 10 = 0 then
      resback := resback + sLineBreak;
  end;
  // Form1.Memo1.Lines.Add(resback);
  Result := resback + mv2;
  freemem:
    for i := 0 to nblock - NCOLORS do
      for j := 0 to NEXTRA do
      begin
        for k := 0 to state[i, j].Count - 1 do
          TNode(state[i, j].Items[k]).Free;
        state[i, j].Free;
      end;
end;

procedure solve(def: TVialsDef);
var
  nd, ndnew: TNode;
  nblockV, i, j, k, klim, x, y, ks, kd, vmin: integer;
  ndlist: TList;
  viS, viD: TVialTopInfo;
  blockdecreaseQ: boolean;
label
  abort;
begin

  if Form1.CBSingle.Checked then
    singleMode := True
  else
    singleMode := False;
  init(False);

  nd := TNode.Create(def);
  sortNode(nd, 0, NVIALS - 1);
  //initial number of blocks (empty vial counts!) - NEMPTYVIAL
  nblockV := nd.nodeBlocks - NEMPTYVIALS;
  for i := 0 to nblockV - NCOLORS do
    for j := 0 to NEXTRA do
      state[i, j] := TList.Create;
  state[0, 0].Add(nd);
  nd.writeHashbit;

  klim := nblockV - NCOLORS - 1 + NEXTRA;
  for k := 0 to klim do
    for y := 0 to Min(k, NEXTRA) do
    begin
      if stop then
        goto abort;
      Application.ProcessMessages;
      x := k - y;
      if x > nblockV - NCOLORS - 1 then
        continue;

      ndlist := state[x, y];
      for i := 0 to ndlist.Count - 1 do
      begin
        nd := TNode(ndlist.Items[i]);
        for ks := 0 to NVIALS - 1 do
        begin
          viS := nd.vial[ks].getTopInfo;
          if viS.empty = NVOLUME then
            continue;//source is empty vial
          for kd := 0 to NVIALS - 1 do
          begin
            if kd = ks then
              continue;//source vial= destination vial
            viD := nd.vial[kd].getTopInfo;

            if singleMode then
            begin
              if (viD.empty = 0)(*destination vial full*) or
                ((viD.empty < NVOLUME) and (viS.topcol <> viD.topcol))
                (*destination not empty and top colors different*) or
                ((viD.empty = NVOLUME) and (viS.topvol = 1) and
                (viS.empty = NVOLUME - 1))
              (*destinaion empty and only one ball in source*) then
                continue;
              if (viS.topvol = 1) and (viS.empty <> NVOLUME - 1) then
                blockdecreaseQ := True
              else
                blockdecreaseQ := False;

              if not blockdecreaseQ and (y = NEXTRA) then
                continue;
              //too many non merging moves

              ndnew := TNode.Create(nd);

              ndnew.vial[kd].color[viD.empty - 1] := TCls(viS.topcol);
              ndnew.vial[ks].color[viS.empty] := EMPTY;

            end
            else
            begin
              if (viD.empty = 0)(*destination vial full*) or
                ((viD.empty < NVOLUME) and (viS.topcol <> viD.topcol))
                (*destination not empty and top colors different*) or
                ((viD.empty = NVOLUME) and (viS.topvol + viS.empty = NVOLUME))
              (*destinaion empty and only one color in source*) then
                continue;

              if (viD.empty >= viS.topvol) and (viS.topvol + viS.empty < NVOLUME) then
                blockdecreaseQ :=
                  True //two color blocks are merged and source vial is not emptied
              else
                blockdecreaseQ := False;
              if not blockdecreaseQ and (y = NEXTRA) then
                continue;
              //too many non merging moves

              vmin := Min(viD.empty, viS.topvol);
              ndnew := TNode.Create(nd);

              for j := 1 to vmin do
              begin
                ndnew.vial[kd].color[viD.empty - j] := TCls(viS.topcol);
                ndnew.vial[ks].color[viS.empty - 1 + j] := EMPTY;
              end;

            end;



            sortNode(ndnew, 0, NVIALS - 1);
            ndnew.hash := ndnew.getHash;
            if ndnew.isHashedQ then
            begin
              ndnew.Free;
              continue; //node presumely already exists
            end;
            ndnew.writeHashbit;
            ndnew.mvInfo.srcVial := nd.vial[ks].pos;
            ndnew.mvInfo.dstVial := nd.vial[kd].pos;

            if blockdecreaseQ then
            begin
              ndnew.mvInfo.merged := True;
              state[x + 1, y].Add(ndnew);
            end
            else
            begin
              ndnew.mvInfo.merged := False;
              state[x, y + 1].Add(ndnew);
            end;

          end;//destination vial;
        end;//source vial
      end;//list interation
    end;

  //Form1.Memo1.Lines.Add(IntToStr(nblockV) + ' ' + IntToStr(NCOLORS));
  //for i := 0 to nblockV - NCOLORS do
  //  for j := 0 to NEXTRA do
  //    Form1.Memo1.Lines.Add(IntToStr(i) + ' ' + IntToStr(j) + ' ' +
  //      IntToStr(state[i, j].Count));

  //for i := 0 to nblockV - NCOLORS do
  //begin
  //  Form1.Memo1.Lines.Add(IntToStr(i));
  //  for j := 0 to NEXTRA do
  //  begin
  //    Form1.Memo1.Lines.Add(IntToStr(j));
  //    for k := 0 to state[i, j].Count - 1 do
  //    begin
  //       Form1.Memo1.Lines.Add(Format('i %d j %d',[i,j]));
  //      TNode(state[i, j][k]).printRaw(Form1.Memo1);
  //    end;

  //  end;
  //end;


  //The Nodelists in state[nblockV- NCOLORS, i] contain all almost solutions
  // with at most EMTYVIALS moves away from solved. We pick one of the shortest.


  abort:
    Form1.Memo1.Lines.Add(retrieveOptimalSolution(nblockV));
  Form1.Memo1.Lines.Add('');

end;



{ TNode }
constructor TNode.Create(t: TVialsDef);
var
  i, nvial: integer;
begin
  nvial := High(t);
  Setlength(self.vial, nvial + 1);
  for i := 0 to nvial do
    self.vial[i] := TVial.Create(t[i], i);
  self.hash := getHash;
end;

constructor TNode.Create(node: TNode);
var
  i, nvial: integer;
begin
  nvial := High(node.vial);
  Setlength(self.vial, nvial + 1);
  for i := 0 to nvial do
  begin
    self.vial[i] := TVial.Create(node.vial[i].color, node.vial[i].pos);
  end;
  self.hash := node.hash;
end;

destructor TNode.Destroy;
var
  n, i: integer;
begin
  n := High(self.vial);
  for i := 0 to n do
    self.vial[i].Destroy;
  Setlength(self.vial, 0);
end;

procedure TNode.printRaw(w: TMemo);
var
  s, sn: string;
  hv, hc, i, j: integer;
begin
  hv := High(self.vial);
  hc := High(self.vial[1].color);
  for i := 0 to hc do
  begin
    s := '';
    for j := 0 to hv do
    begin
      sn := IntToStr(byte(self.vial[j].color[i]));
      s := s + Format('%5s', [sn]);
    end;
    w.Lines.Add(s);
  end;
  w.Lines.Add('');
end;

procedure TNode.print(w: TMemo);
var
  s, sn: string;
  hv, hc, i, j: integer;
  vialpos: array of byte;
begin
  hv := High(self.vial);
  hc := High(self.vial[1].color);
  SetLength({%H-}vialpos, hv + 1); //{%H-} to supress warning
  for i := 0 to hv do
    vialpos[self.vial[i].pos] := i;
  for i := 0 to hc do
  begin
    s := '';
    for j := 0 to hv do
    begin
      sn := IntToStr(byte(self.vial[vialpos[j]].color[i]));
      s := s + Format('%5s', [sn]);
    end;
    w.Lines.Add(s);
  end;
  w.Lines.Add('');
end;

function TNode.getHash: UInt32;
var
  p, v: integer;
begin
  Result := 0;
  for v := 0 to NVIALS - 1 do
    for p := 0 to NVOLUME - 1 do
    begin
      Result := Result xor hsh[integer(self.vial[v].color[p]), p, v];
    end;
end;

procedure TNode.writeHashbit;
var
  base, offset: integer;
begin
  base := self.hash div 64;
  offset := self.hash mod 64;
  hashbits[base] := hashbits[base] or (UInt64(1) shl offset);
end;

function TNode.isHashedQ: boolean;
var
  base, offset: integer;
begin
  base := self.hash div 64;
  offset := self.hash mod 64;
  if (hashbits[base] and (UInt64(1) shl offset)) <> 0 then
    Result := True
  else
    Result := False;
end;

function TNode.nodeBlocks: integer;
var
  i: integer;
begin
  Result := 0;
  for i := 0 to NVIALS - 1 do
  begin
    Inc(Result, self.vial[i].vialBlocks);
    //we count emtpty vials as 1 block
    if self.vial[i].color[NVOLUME - 1] = EMPTY then
      Inc(Result);
  end;

end;

function TNode.equalQ(node: TNode): boolean;
  //test vials for equality. vials are assumed to be already sorted.
var
  i, j: integer;
begin
  Result := True;
  for i := 0 to NVIALS - 1 do
    for j := 0 to NVOLUME - 1 do
    begin
      if self.vial[i].color[j] <> node.vial[i].color[j] then
        exit(False);
    end;
end;

function TNode.lastmoves: string;
  //we assume nd is sorted
var
  i, src, dst: integer;
  ft: string;
begin
  if NVIALS > 9 then
    ft := '%2d->%2d  '
  else
    ft := '%d->%d  ';
  Result := '';

  if NEMPTYVIALS = 1 then
  begin
    if Form1.CBSingle.Checked then
      for i := 0 to self.vial[0].getTopInfo.topvol - 1 do
        Result := Result + Format(ft, [self.vial[0].pos + 1, self.vial[1].pos + 1])
    else
    if self.vial[0].getTopInfo.topvol > 0 then
      Result := Result + Format(ft, [self.vial[0].pos + 1, self.vial[1].pos + 1]);
    if Result='' then Exit('Puzzle is solved!') else Exit(Result);
  end;




  //NEMTYVIALS=2
  if self.vial[3].getTopInfo.empty = 0 then //only one color needs to be handled
  begin
    if Form1.CBSingle.Checked then
    begin
      for i := 0 to self.vial[0].getTopInfo.topvol - 1 do
        Result := Result + Format(ft, [self.vial[0].pos + 1, self.vial[2].pos + 1]);

      for i := 0 to self.vial[1].getTopInfo.topvol - 1 do
        Result := Result + Format(ft, [self.vial[1].pos + 1, self.vial[2].pos + 1]);
    end
    else
    begin
      if self.vial[0].getTopInfo.topvol > 0 then
        Result := Result + Format(ft, [self.vial[0].pos + 1, self.vial[2].pos + 1]);
      if self.vial[1].getTopInfo.topvol > 0 then
        Result := Result + Format(ft, [self.vial[1].pos + 1, self.vial[2].pos + 1]);
    end;
  end
  else //two colors
  begin
    src := 0;
    if self.vial[src].getTopInfo.topcol = self.vial[2].getTopInfo.topcol then
      dst := 2
    else
      dst := 3;
    if Form1.CBSingle.Checked then
      for i := 0 to self.vial[src].getTopInfo.topvol - 1 do
        Result := Result + Format(ft, [self.vial[src].pos + 1, self.vial[dst].pos + 1])
    else
      Result := Result + Format(ft, [self.vial[src].pos + 1, self.vial[dst].pos + 1]);
    src := 1;
    if self.vial[src].getTopInfo.topcol = self.vial[2].getTopInfo.topcol then
      dst := 2
    else
      dst := 3;
    if Form1.CBSingle.Checked then
      for i := 0 to self.vial[src].getTopInfo.topvol - 1 do
        Result := Result + Format(ft, [self.vial[src].pos + 1, self.vial[dst].pos + 1])
    else
      Result := Result + Format(ft, [self.vial[src].pos + 1, self.vial[dst].pos + 1]);
  end;

  if Result = '' then
    Result := 'Puzzle is solved!';
end;



function TNode.Nlastmoves(singlemode: boolean): integer;
var
  i, n: integer;
begin
  n := 0;
  if singlemode then
  begin
    Result := 0;
    for i := 0 to NEMPTYVIALS - 1 do
      Inc(Result, self.vial[i].getTopInfo.topvol);

  end
  else
  begin
    Result := NEMPTYVIALS;
    for i := 0 to NEMPTYVIALS - 1 do
      if vial[i].color[NVOLUME - 1] = EMPTY then
        Dec(Result);
  end;
end;

{ TVial }

constructor TVial.Create(var c: array of TCls; p: UInt8);
var
  i: integer;
begin
  Setlength(self.color, NVOLUME);
  for i := 0 to NVOLUME - 1 do
    self.color[i] := c[i];
  self.pos := p;
end;

destructor TVial.Destroy;
begin
  Setlength(self.color, 0);
end;

function TVial.getTopInfo: TVialTopInfo;
var
  i, cl: integer;
begin
  Result.topcol := 0;
  Result.empty := NVOLUME;
  Result.topvol := 0;
  if self.color[NVOLUME - 1] = EMPTY then
    Exit(Result);   //empty vial

  for i := 0 to NVOLUME - 1 do
    if self.color[i] <> EMPTY then
    begin
      cl := integer(self.color[i]);
      Result.topcol := cl;
      Result.empty := i;
      Break;
    end;
  Result.topvol := 1;
  for i := Result.empty + 1 to NVOLUME - 1 do
    if cl = integer(self.color[i]) then
      Inc(Result.topvol)
    else
      Break;
end;

function TVial.vialBlocks: integer;
var
  i: integer;
begin
  Result := 1;
  for i := 0 to NVOLUME - 2 do
    if self.color[i + 1] <> self.color[i] then
      Inc(Result);
  if self.color[0] = EMPTY then
    Dec(Result);
end;

{ TForm1 }

procedure TForm1.FormCreate(Sender: TObject);

begin
  NVOLUME := 5;
  NEMPTYVIALS := 2;
  NCOLORS := 9;
  NVIALS := NCOLORS + NEMPTYVIALS;
  NEXTRA := NCOLORS;
  singlemode := False;
  init;
end;

procedure TForm1.FormKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
begin
  if (ssShift in Shift) or (ssCtrl in Shift) then
    shifted := True
  else
    shifted := False;
  Panel1.Invalidate;
end;



procedure TForm1.FormKeyUp(Sender: TObject; var Key: word; Shift: TShiftState);
begin
  begin
    if (ssShift in Shift) or (ssCtrl in Shift) then
      shifted := True
    else
      shifted := False;
    Panel1.Invalidate;
  end;
end;



procedure TForm1.BSolveClick(Sender: TObject);
var
  nd: TNode;
begin

  if BSolve.Caption = 'Solve optimal' then
  begin
    stop := False;
    BSolve.Caption := 'Abort';
  end
  else
  begin
    stop := True;
    Exit;
  end;

  NColorsSpin.Enabled := False;
  NFreeVialSpin.Enabled := False;
  NVolumeSpin.Enabled := False;

  NCOLORS := NColorsSpin.Value;
  NEMPTYVIALS := NFreeVialSpin.Value;
  NVOLUME := NVolumeSpin.Value;
  NVIALS := NCOLORS + NEMPTYVIALS;

  init(False);


  Panel1.Invalidate;

  nd := TNode.Create(globVialdef);
  solve(globVialdef);
  nd.Free;
  BSolve.Caption := 'Solve optimal';
  NColorsSpin.Enabled := True;
  NFreeVialSpin.Enabled := True;
  NVolumeSpin.Enabled := True;
end;

procedure TForm1.BUndoClick(Sender: TObject);
var
  i, j: integer;
begin
  if undoHist < 0 then
    Exit;
  for i := 0 to NVIALS - 1 do
    for j := 0 to NVOLUME - 1 do
      globVialdef[i, j] := vialsDefHist[undoHist][i, j];
  SetLength(vialsDefHist[undoHist], 0, 0);
  Dec(undoHist);
  Form1.Caption := 'ColorSortOptimalSolver - ' + IntToStr(undoHist + 1) + ' move(s)';
  Panel1.Invalidate;
end;

procedure TForm1.CBSingleChange(Sender: TObject);
begin
  if CBSingle.Checked then
    singleMode := True
  else
    singleMode := False;
end;

procedure TForm1.FormClose(Sender: TObject; var CloseAction: TCloseAction);
var
  i: integer;
begin
  for i := 0 to undoHist do
    SetLength(vialsDefHist[i], 0, 0);
end;

procedure TForm1.NColorsSpinChange(Sender: TObject);
begin
  NCOLORS := NColorsSpin.Value;
  NVIALS := NCOLORS + NEMPTYVIALS;
  init;
end;

procedure TForm1.NFreeVialSpinChange(Sender: TObject);
begin
  NEMPTYVIALS := NFreeVialSpin.Value;
  NVIALS := NCOLORS + NEMPTYVIALS;
  init;
end;

procedure TForm1.NVolumeSpinChange(Sender: TObject);
begin
  NVOLUME := NVolumeSpin.Value;
  init;
end;



procedure TForm1.Panel1MouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: integer);
var
  i, i1, j, ks, kd, tmp: integer;
  p: TPanel;
  xhVial, xhBlock, yhBlock, dx, dy: double;
  scol: TCls;
label
  edit, noswap;
begin
  p := Sender as TPanel;
  xhVial := ((p.Width - (NVIALS + 1) * XOFF)) / NVIALS;
  if shifted then
    goto edit;//edit modus
  for i := 0 to NVIALS - 1 do
  begin
    dx := XOFF + i * (xhVial + XOFF);
    if (Round(dx) <= X) and (X < Round(dx + xhVial)) then
    begin
      if srcVial > -1 then
      begin
        if srcVial = i then
        begin
          srcVial := -1;
          dstVial := -1;
        end
        else
        begin

          dstVial := i;

          //try to pour src into dst
          if globVialdef[srcVial, NVOLUME - 1] = EMPTY then
          begin
            srcVial := -1;
            dstVial := -1;
            p.Invalidate;
            Exit;//empty source
          end
          else
          begin
            for j := 0 to NVOLUME - 1 do
            begin
              if globVialdef[srcVial, j] = EMPTY then
                continue
              else
              begin
                ks := j;
                break;
              end;
            end;
            if globVialdef[dstVial, NVOLUME - 1] = EMPTY then
              kd := NVOLUME
            else
            begin
              for j := 0 to NVOLUME - 1 do
              begin
                if globVialdef[dstVial, j] = EMPTY then
                  continue
                else
                begin
                  kd := j;
                  break;
                end;
              end;
            end;



            if (kd < NVOLUME) and (globVialdef[srcVial, ks] <>
              globVialdef[dstVial, kd]) or (kd = 0) then  //kd=0 is full vial
            begin
              srcVial := -1;
              dstVial := -1;
              p.Invalidate;
              Exit;
            end
            else
            begin
              Inc(undoHist); //save old position in history
              SetLength(vialsDefHist[undoHist], NVIALS, NVOLUME);
              for i1 := 0 to NVIALS - 1 do
                for j := 0 to NVOLUME - 1 do
                  vialsDefHist[undoHist][i1, j] := globVialdef[i1, j];

              if not singleMode then
              begin
                scol := globVialdef[srcVial, ks];
                repeat
                  globVialdef[dstVial, kd - 1] := globVialdef[srcVial, ks];
                  globVialdef[srcVial, ks] := EMPTY;
                  Inc(ks);
                  Dec(kd);
                until (ks = NVOLUME) or (kd = 0) or (globVialdef[srcVial, ks] <> scol);

              end
              else
              begin
                globVialdef[dstVial, kd - 1] := globVialdef[srcVial, ks];
                globVialdef[srcVial, ks] := EMPTY;
              end;


              srcVial := -1;
              dstVial := -1;
              Form1.Caption :=
                'ColorSortOptimalSolver - ' + IntToStr(undoHist + 1) + ' move(s)';
              p.Invalidate;
            end;
          end;
        end;

      end
      else
        srcVial := i;
      p.Invalidate;
      break;
    end;
  end;
  Exit;
  edit: //exchange two blocks
    xhBlock := ((p.Width - (NVIALS + 1) * XOFF)) / NVIALS;
  yhBlock := (p.Height - 2 * YOFF) / NVOLUME;
  for i := 0 to NVIALS - 1 do
  begin
    dx := XOFF + i * (xhVial + XOFF);
    if (Round(dx) <= X) and (X < Round(dx + xhVial)) then  //Vial i
      for j := 0 to NVOLUME - 1 do
      begin
        dy := YOFF + j * yhBlock;
        if (Round(dy) <= Y) and (Y < Round(dy + yhBlock)) then //Block j
          //Memo1.Lines.Add(Format('%d %d',[i,j]));
          if srcblock > -1 then
          begin
            if (srcvial = i) and (srcblock = j) then
            begin
              srcvial := -1;
              srcblock := -1;
              dstvial := -1;
              dstblock := -1;
            end
            else
            begin
              dstblock := j;
              dstvial := i;
              //some color swaps which use empty blocks are forbidden
              if (globVialdef[dstvial, dstblock] = EMPTY) then
              begin
                tmp := srcblock;
                srcblock := dstblock;
                dstblock := tmp;
                tmp := srcvial;
                srcvial := dstvial;
                dstvial := tmp;
              end;
              if (globVialdef[srcvial, srcblock] = EMPTY) then
              begin
                if (srcblock < NVOLUME - 1) and
                  (globVialdef[srcvial, srcblock + 1] = EMPTY) or
                  (dstblock > 0) and (globVialdef[dstvial, dstblock - 1] <>
                  EMPTY) or ((srcvial = dstvial) and (dstblock = srcblock + 1))
                then
                  goto noswap;
              end;
              scol := globVialdef[srcvial, srcblock];
              globVialdef[srcvial, srcblock] := globVialdef[dstvial, dstblock];
              globVialdef[dstvial, dstblock] := scol;
              Panel1.Invalidate;
              noswap:
                srcvial := -1;
              srcblock := -1;
              dstvial := -1;
              dstblock := -1;
              Exit;
            end;

          end
          else
          begin
            srcblock := j;
            srcvial := i;
            Exit;
          end;

      end; //j

  end;
end;

procedure plotVial(p: TPanel; idx: integer);
//idx is zero based
var
  cv: TCanvas;
  xhVial, yVial, dx: double;
begin

  xhVial := ((p.Width - (NVIALS + 1) * XOFF)) / NVIALS;
  yVial := p.Height - 2 * YOFF;
  dx := XOFF + idx * (xhVial + XOFF);
  cv := p.Canvas;
  if (srcVial = idx) and not shifted then
  begin
    cv.Pen.Color := clBlack;
    cv.Pen.Width := 12;
  end
  //else if dstVial = idx then
  //begin
  //cv.Pen.Color := clRed;
  //cv.Pen.Width := 8;
  //end
  else
  begin
    cv.Pen.Color := clBlack;
    cv.Pen.Width := 2;
  end;

  cv.Line(Round(dx), YOFF, Round(dx + xhVial), YOFF);
  cv.LineTo(Round(dx + xhVial), Round(YOFF + yVial));
  cv.LineTo(Round(dx), Round(YOFF + yVial));
  cv.LineTo(Round(dx), YOFF);
  cv.Brush.Style := bsClear;
  cv.Font.Size := 12;
  cv.Font.Color := clBlack;
  cv.TextOut(Round(dx + xhVial / 2.3), Round(YOFF + yVial), IntToStr(idx + 1));
end;

procedure plotBlock(p: TPanel; nv, np, cl: integer);
//nv: vial, np:position in vial, cl: color
var
  cv: TCanvas;
  xhBlock, yhBlock, dx, dy: double;
begin
  xhBlock := ((p.Width - (NVIALS + 1) * XOFF)) / NVIALS;
  yhBlock := (p.Height - 2 * YOFF) / NVOLUME;
  dx := XOFF + nv * (xhBlock + XOFF);
  dy := YOFF + np * yhBlock;
  cv := p.Canvas;
  cv.Pen.Width := 2;
  cv.Brush.Color := cols[cl];
  if shifted then
    cv.Pen.Color := clBlack
  else
    cv.Pen.Color := cols[cl];
  cv.Rectangle(Round(dx), Round(dy), Round(dx + xhBlock), Round(dy + yHBlock));
end;



procedure TForm1.Panel1Paint(Sender: TObject);
var
  i, j: integer;
  cv: TCanvas;
begin
  cv := panel1.Canvas;
  for i := 0 to NVIALS - 1 do
  begin
    for j := 0 to NVOLUME - 1 do
      plotBlock(Panel1, i, j, integer(globVialdef[i, j]));
    plotVial(Panel1, i);
  end;
  if shifted then
  begin
    cv.Font.Size := 10;
    cv.Font.Color := clRed;
    if srcblock = -1 then
      cv.TextOut(0, 0, 'Select first block')
    else
      cv.TextOut(0, 0, 'Select second block');

  end;
end;

procedure TForm1.TBRandomClick(Sender: TObject);
var
  tmp: TCls;
  i, j: integer;
begin
  NCOLORS := NColorsSpin.Value;
  NEMPTYVIALS := NFreeVialSpin.Value;
  NVOLUME := NVolumeSpin.Value;
  NVIALS := NCOLORS + NEMPTYVIALS;


  init;

  Randomize;
  //Fisher-Jates-Shuffle
  for i := NVOLUME * NCOLORS - 1 downto 1 do
  begin
    j := Random(i + 1);
    tmp := globVialdef[j div NVOLUME, j mod NVOLUME];
    globVialdef[j div NVOLUME, j mod NVOLUME] :=
      globVialdef[i div NVOLUME, i mod NVOLUME];
    globVialdef[i div NVOLUME, i mod NVOLUME] := tmp;
  end;

  Panel1.Invalidate;

  //nd := TNode.Create(globVialdef);
  //nd.print(Memo1);
  //solve(globVialdef);
  //Memo1.Lines.Add('done!');
  //nd.Free;
end;

end.
