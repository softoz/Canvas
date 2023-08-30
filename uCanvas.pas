unit uCanvas;

(* Generic off-screen drawing canvas *)
(* 2016-23 pjde *)

{$mode objfpc}{$H+}
{
Image Resize algorithnm based on code by Gustavo Daud.

 **********************************************************************}

{Tweaked to run on Ultibo Canvas pjde 2018 }
{$H+}

interface

uses
  Classes, SysUtils, FrameBuffer, uFontInfo, Ultibo, freetypeh, FPImage, FPReadPNG, FPReadBMP, FPReadJPEG;

type
  TImage32Value = TFPCompactImgRGBA8BitValue;
  PImage32Value = PFPCompactImgRGBA8BitValue;

  { TImage32 }

  TImage32 = class (TFPCompactImgRGBA8Bit)
  public
    function GetScanline (no : integer) : PImage32Value;
    property Data : PImage32Value read FData;
  end;

  { TLibImage }

  TLibImage = class
    Image : TImage32;
    Path : string;
    Name : string;
    Width, Height : integer;
    DefImage : boolean;
    procedure Assign (Other : TLibImage);
    constructor Create;
    destructor Destroy; override;
  end;

  { TImageLib }

  TImageLib = class
  private
    function GetItem (Index: Integer): TLibImage;
    procedure SetItem (Index: Integer; const Value: TLibImage);
  public
    FList : TList;
    property Items[Index: Integer]: TLibImage read GetItem write SetItem; default;
    constructor Create;
    destructor Destroy; override;
    function Count : integer;
    procedure Sort;
    function Add (anImage : TLibImage) : integer;  overload;
    function Add (aName : string; aPng : TImage32) : integer; overload;
    procedure Clear;
    procedure Remove (anImage : TLibImage);
    function IndexOf (anImage : TLibImage) : integer;
    function Rename (OldName, NewName : string) : boolean;
    function GetPng (byIndex : integer) : TImage32; overload;
    function GetPng (byName : string) : TImage32; overload;
    function GetPng (byName : string; w, h : integer) : TImage32; overload;
    function GetImage (byName : string) : TLibImage;
    function SaveToResource (aRes : THandle) : boolean;
  end;

{ TCanvas }

  TCanvas = class
  public
    ColourFormat : LongWord;
    Width, Height : integer;
    Left, Top : integer;
    Buffer : PByteArray;
    BufferSize : integer;
    BitCount : integer;
    procedure SetSize (w, h : integer; cf : LongWord);
    procedure Fill (Col : LongWord); overload;
    procedure Fill (Rect : Ultibo.TRect; Col : LongWord); overload;
    function GetScanLine (no : integer) : PLongWord;
    procedure DrawText (x, y : integer; Text, Font : string; FontSize : integer; Col : LongWord; Alpha : byte = 255); overload;
    procedure DrawText (x, y : integer; Text : string; Font : TFontInfo; FontSize : integer; Col : LongWord; Alpha : byte = 255); overload;
    procedure Flush (FrameBuff : PFrameBufferDevice; x, y : integer); overload;
    procedure Flush (FrameBuff : PFrameBufferDevice); overload;
    procedure Assign (anOther : TCanvas);
    procedure DrawCanvas (aCanvas : TCanvas; x, y : integer);
    procedure DrawImage (anImage : TImage32; x, y : integer; Alpha : byte = 255);  overload;
    procedure DrawImage (anImage : TImage32; x, y, w, h : integer; Alpha : byte = 255); overload;
    constructor Create;
    destructor Destroy; override;
  end;

function SetRect (Left, Top, Right, Bottom : long) : Ultibo.TRect;
function GetRValue (c : LongWord) : byte;
function GetGValue (c : LongWord) : byte;
function GetBValue (c : LongWord) : byte;
function rgb (r, g, b : byte) : LongWord; inline;

procedure ReSize (dst, src : TImage32);
procedure CollectImages;

function TextExtents (Text, Font : string; FontSize : integer) : FT_Vector; overload;
function TextExtents (Text : string; Font : TFontInfo; FontSize : integer) : FT_Vector; overload;

var
  Images : TImageLib;

implementation

uses GlobalConst, uLog, Math;

var
  FTLib : PFT_Library;                // handle to FreeType library
  i : integer;

function FT_New_Memory_Face (alibrary: PFT_Library; file_base: pointer; file_size: longint; face_index: integer; var face: PFT_Face) : integer; cdecl; external freetypedll Name 'FT_New_Memory_Face';

const
  DPI = 72;

procedure ReSize (dst, src : TImage32);
var
  xscale, yscale : single;
  sfrom_y, sfrom_x : single;
  ifrom_y, ifrom_x : integer;
  to_y, to_x : integer;
  weight_x, weight_y : array[0..1] of single;
  weight : single;
  new_red, new_green : integer;
  new_blue, new_alpha : integer;
  total_red, total_green : single;
  total_blue, total_alpha: single;
  ix, iy : integer;
  sli, slo : PImage32Value;
begin
  xscale := dst.Width / (src.Width - 1);
  yscale := dst.Height / (src.Height - 1);
  for to_y := 0 to dst.Height - 1 do
    begin
      sfrom_y := to_y / yscale;
      ifrom_y := Trunc(sfrom_y);
      weight_y[1] := sfrom_y - ifrom_y;
      weight_y[0] := 1 - weight_y[1];
      for to_x := 0 to dst.Width - 1 do
        begin
          sfrom_x := to_x / xscale;
          ifrom_x := Trunc (sfrom_x);
          weight_x[1] := sfrom_x - ifrom_x;
          weight_x[0] := 1 - weight_x[1];
          total_red   := 0.0;
          total_green := 0.0;
          total_blue  := 0.0;
          total_alpha  := 0.0;
          for ix := 0 to 1 do
            begin
              for iy := 0 to 1 do
                begin
                  sli := src.GetScanline (ifrom_y + iy);
                  new_red := sli[ifrom_x + ix].R;
                  new_green := sli[ifrom_x + ix].G;
                  new_blue := sli[ifrom_x + ix].B;
                  new_alpha := sli[ifrom_x + ix].A;
                  weight := weight_x[ix] * weight_y[iy];
                  total_red := total_red  + new_red  * weight;
                  total_green := total_green + new_green * weight;
                  total_blue := total_blue + new_blue  * weight;
                  total_alpha := total_alpha + new_alpha  * weight;
                end;
            end;
          slo := dst.GetScanLine (to_y);
          slo[to_x].R := Round (total_red);
          slo[to_x].G := Round (total_green);
          slo[to_x].B := Round (total_blue);
          slo[to_x].A := Round (total_alpha);
        end;
    end;
end;

function FT_HAS_KERNING (face : PFT_Face) : boolean;
begin
  Result := (face^.face_flags and FT_FACE_FLAG_KERNING) <> 0;
end;

function SetRect (Left, Top, Right, Bottom : long) : Ultibo.TRect;
begin
  Result.left := Left;
  Result.top := Top;
  Result.right := Right;
  Result.bottom := Bottom;
end;

function GetRValue (c : LongWord) : byte; inline;
begin
  Result := (c and $ff0000) shr 16;
end;

function GetGValue (c : LongWord) : byte; inline;
begin
  Result :=  (c and $ff00) shr 8;
end;

function GetBValue (c : LongWord) : byte; inline;
begin
  Result := c and $ff;
end;

function rgb (r, g, b : byte) : LongWord; inline;
begin
  Result := $ff000000 + (r shl 16) + (g shl 8) + b;
end;

{ TImage32 }

function TImage32.GetScanline (no: integer) : PImage32Value;
begin
  LongWord (Result) := LongWord (FData) + (no * Width * SizeOf (TImage32Value));
end;

{ TLibImage }
procedure TLibImage.Assign (Other : TLibImage);
begin
  if Other = nil then exit;
  Name := Other.Name;
  Path := Other.Path;
  Width := Other.Width;
  Height := Other.Height;
  DefImage := Other.DefImage;
  Image.Assign (Other.Image);
end;

constructor TLibImage.Create;
begin
  Image := TImage32.Create (0, 0);
  Path := '';
  Name := '';
  Width := 0;
  Height := 0;
  DefImage := false;
end;

destructor TLibImage.Destroy;
begin
  Image.Free;
  inherited;
end;

{TImageLib }

function TImageLib.Add (anImage : TLibImage): integer;
begin
  FList.Add (anImage);
  Result := FList.Count - 1;
end;

function TImageLib.Add (aName : string; aPng : TImage32) : integer;
var
  anImage : TLibImage;
begin
  anImage := TLibImage.Create;
  anImage.Image := aPng;
  anImage.Name := aName;
  Result := Add (anImage);
end;

procedure TImageLib.Clear;
var
  i : integer;
begin
  for i := 0 to FList.Count - 1 do TLibImage (FList[i]).Free;
  FList.Clear;
end;

function TImageLib.Count : integer;
begin
  Result := FList.Count;
end;

constructor TImageLib.Create;
begin
  inherited;
  FList := TList.Create;
end;

destructor TImageLib.Destroy;
var
  i : integer;
begin
  for i := 0 to FList.Count - 1 do TLibImage (FList[i]).Free;
  FList.Free;
  inherited;
end;

function TImageLib.GetImage (byName : string) : TLibImage;
var
  i : integer;
begin
  for i := 0 to FList.Count - 1 do
    begin
      Result := TLibImage (FList[i]);
      if CompareText (Result.Name, byName) = 0 then exit;
    end;
  Result := nil;
end;

function TImageLib.GetItem (Index : Integer) : TLibImage;
begin
  if (Index >= 0) and (Index < FList.Count) then
    Result := TLibImage (FList[Index])
  else
    Result := nil;
end;

function TImageLib.GetPng (byIndex : integer) : TImage32;
var
  anImage : TLibImage;
begin
  anImage := Items[byIndex];
  if anImage <> nil then
    Result := anImage.Image
  else
    Result := nil;
end;

function TImageLib.GetPng (byName : string) : TImage32;
var
  i : integer;
  anImage : TLibImage;
begin
  for i := 0 to FList.Count - 1 do
    begin
      anImage := TLibImage (FList[i]);
      if (CompareText (anImage.Name, byName) = 0) and (anImage.DefImage) then
        begin
          Result := anImage.Image;
          exit;
        end;
     end;
   Result := nil;
end;

function TImageLib.GetPng (byName : string; w, h : integer) : TImage32;
var
  i : integer;
  anImage : TLibImage;
begin
  for i := 0 to FList.Count - 1 do
    begin
      anImage := TLibImage (FList[i]);
      if (CompareText (anImage.Name, byName) = 0) and (anImage.Width = w) and
         (anImage.Height = h) then
        begin
          Result := anImage.Image;
          exit;
        end;
     end;
   Result := nil;
end;

function TImageLib.IndexOf (anImage : TLibImage) : integer;
begin
  Result := FList.IndexOf (anImage);
end;

procedure TImageLib.Remove (anImage : TLibImage);
begin
  if anImage = nil then exit;
  FList.Remove (anImage);
  anImage.Free;
end;

function TImageLib.Rename (OldName, NewName : string): boolean;
var
  anImage : TLibImage;
begin
  Result := false;
  anImage := GetImage (NewName);
  if anImage <> nil then exit; // aleady present
  anImage := GetImage (OldName);
  if anImage = nil then exit;
  anImage.Name := NewName;
end;

function TImageLib.SaveToResource (aRes : THandle) : boolean;
begin
  Result := false;
end;

procedure TImageLib.SetItem (Index : Integer; const Value : TLibImage);
begin
  if (Index >= 0) and (Index < FList.Count) then
    FList[Index] := Value;
end;

function ImageSort (Item1, Item2: Pointer) : integer;
begin
  Result := CompareText (TLibImage (Item1).Name, TLibImage (Item2).Name);
end;

procedure TImageLib.Sort;
begin
  FList.Sort (@ImageSort);
end;

{ TCanvas }

procedure TCanvas.DrawText (x, y : integer; Text, Font : string; FontSize : integer; Col : LongWord; Alpha : byte = 255); overload;
var
  anInfo : TFontInfo;
  fn : string;
begin
   if ExtractFileExt (Font) = '' then
    fn := Font + '.ttf'
  else
    fn := Font;
  anInfo := GetFontByName (fn, true);
  DrawText (x, y, Text, anInfo, FontSize, Col, Alpha);
end;

procedure TCanvas.DrawText (x, y : integer; Text : string; Font : TFontInfo; FontSize : integer; Col : LongWord; Alpha : byte = 255); overload;
var
  err : integer;
  aFace : PFT_Face;
  fn : string;
  i, tx, ty : integer;
  kerning : boolean;
  glyph_index,
  prev : cardinal;
  delta : FT_Vector;
  bg : LongWord;
  CharCode : cardinal;
  FirstByte, UTF8Bytes : byte;

  procedure DrawChar (b : FT_Bitmap; dx, dy : integer);
  var
    i , j : integer;
    x_max, y_max : integer;
    p, q : integer;
    fm : PByte;
    rd, gn, bl : byte;
    cp : PLongWord; // canvas pointer
   begin
    x_max := dx + b.width;
    y_max := dy + b.rows;
//    Log ('dx ' + InttoStr (dx) + ' dy ' +  IntToStr (dy) + ' x max ' +  IntToStr (x_max) + ' y max ' + IntToStr (y_max));
    case ColourFormat of
      COLOR_FORMAT_ARGB32 : {32 bits per pixel Red/Green/Blue/Alpha (RGBA8888)}
        begin
          q := 0;
          for j := dy to y_max - 1 do
            begin
              if (j >= 0) and (j < Height) then
                begin
                  LongWord (cp) := LongWord (Buffer) + ((j * Width) + dx) * 4;
                  p := 0;
                  for i := dx to x_max - 1 do
                    begin
                      if (i >= 0) and (i < Width) then
                        begin
                          LongWord (fm) := LongWord (b.buffer) + q * b.width + p; // read alpha value of font char
                          fm^ := (fm^ * alpha) div 255;
                          rd := ((GetRValue (Col) * fm^) + (GetRValue (cp^) * (255 - fm^))) div 255;
                          gn := ((GetGValue (Col) * fm^) + (GetGValue (cp^) * (255 - fm^))) div 255;
                          bl := ((GetBValue (Col) * fm^) + (GetBValue (cp^) * (255 - fm^))) div 255;
                          cp^ := rgb (rd, gn, bl);
                        end;
                      p := p + 1;
                      Inc (cp, 1);
                    end;
                  q := q + 1;
                end;
            end;
        end; // colour format
      end; // case
  end;

begin
  if not Assigned (FTLib) then exit;
  aFace := nil;
  tx := x;
  ty := y;
  delta.x := 0;
  delta.y := 0;
  if Font = nil then exit;
  err := FT_New_Memory_Face (FTLib, Font.Stream.Memory, Font.Stream.Size, 0, aFace);
  if err = 0 then  // if font face loaded ok
    begin
      err := FT_Set_Char_Size (aFace,                   // handle to face object
             0,                                         // char_width in 1/64th of points - Same as height
             FontSize * 64,                                   // char_height in 1/64th of points
             DPI,                                       // horizontal device resolution
             0);                                        // vertical device resolution
      if err = 0 then
        begin
          prev := 0;    // no previous char
          kerning := FT_HAS_KERNING (aFace);
          i := 1;
          while i <= length (Text) do
            begin
              FirstByte := byte (Text[1]);
              UTF8Bytes := 1;
              if FirstByte >= $80 then //  110xxxxx 10xxxxxx
                UTF8Bytes := UTF8Bytes + 1;
              if FirstByte >= $E0 then //  1110xxxx 10xxxxxx 10xxxxxx
                UTF8Bytes := UTF8Bytes + 1;
              if FirstByte >= $F0 then //  11110zzz 11zzxxxx 10xxxxxx 10xxxxxx
                UTF8Bytes := UTF8Bytes + 1;
              CharCode := 0;
              if i + (UTF8Bytes - 1) <= length (Text) then
                case UTF8Bytes of
                  1 : CharCode := cardinal (Text[i]);                              // 1Byte
                  2 : CharCode := (cardinal (Text[i]) and $1F ) * $40 +            // 000xxxxx
                                  (cardinal (Text[i + 1]) and $3F);                // 00xxxxxx
                  3 : CharCode := (cardinal (Text[i]) and $0F) * $1000 +           // 0000xxxx
                                  (cardinal (Text[i + 1]) and $3F) * $40 +         // 00xxxxxx
                                  (cardinal (Text[i + 2]) and $3F);                // 00xxxxxx
                  4 : CharCode := (cardinal (Text[i]) and $07) * $4000 +           // 0000xxxx
                                  (cardinal (Text[i + 1]) and $0F) * $1000 +       // 0000xxxx
                                  (cardinal (Text[i + 2]) and $3F) * $40 +         // 00xxxxxx
                                  (cardinal (Text[i + 3]) and $3F);                // 00xxxxxx
                  end;
              i := i + UTF8Bytes;
              if CharCode <> 0 then
                begin
                  glyph_index := FT_Get_Char_Index (aFace, CharCode);
                  if kerning and (prev <> 0) and (glyph_index <> 0) then
                    begin
                      FT_Get_Kerning (aFace, prev, glyph_index, FT_KERNING_DEFAULT, &delta);
                      tx := tx + delta.x div 64;
                    end;
                  // load glyph image into the slot (erase previous one)
                  err := FT_Load_Glyph (aFace, glyph_index, FT_LOAD_RENDER);
                  if err > 0 then continue;                // ignore errors
                  // now draw to our target surface
                  DrawChar (aFace^.glyph^.bitmap, tx + aFace^.glyph^.bitmap_left,
                              ty - aFace^.glyph^.bitmap_top);
                  tx := tx + aFace^.glyph^.advance.x div 64;
                  prev := glyph_index;
                end;
            end;
        end;
      FT_Done_Face (aFace);
    end;
end;

procedure TCanvas.SetSize (w, h : integer; cf : LongWord);
var
  bc : integer;
begin
  if Buffer <> nil then FreeMem (Buffer);
  Buffer := nil;
  Width := w;
  Height := h;
  ColourFormat := cf;
  case ColourFormat of
    COLOR_FORMAT_ARGB32, {32 bits per pixel Alpha/Red/Green/Blue (ARGB8888)}
    COLOR_FORMAT_ABGR32, {32 bits per pixel Alpha/Blue/Green/Red (ABGR8888)}
    COLOR_FORMAT_RGBA32, {32 bits per pixel Red/Green/Blue/Alpha (RGBA8888)}
    COLOR_FORMAT_BGRA32 : bc := 4; {32 bits per pixel Blue/Green/Red/Alpha (BGRA8888)}
    COLOR_FORMAT_RGB24, {24 bits per pixel Red/Green/Blue (RGB888)}
    COLOR_FORMAT_BGR24  : bc := 3; {24 bits per pixel Blue/Green/Red (BGR888)}
    // COLOR_FORMAT_RGB18  = 6; {18 bits per pixel Red/Green/Blue (RGB666)}
    COLOR_FORMAT_RGB16, {16 bits per pixel Red/Green/Blue (RGB565)}
    COLOR_FORMAT_RGB15  : bc := 2; {15 bits per pixel Red/Green/Blue (RGB555)}
    COLOR_FORMAT_RGB8   : bc := 1; {8 bits per pixel Red/Green/Blue (RGB332)}
    else bc := 0;
    end;
  BufferSize := Width * Height * bc;
  if BufferSize > 0 then
    begin
      GetMem (Buffer, BufferSize);
      FillChar (Buffer^, BufferSize, 0);
    end;
end;

procedure TCanvas.Fill (Col: LongWord);
var
  Rect : Ultibo.TRect;
begin
  Rect := SetRect (0, 0, Width - 1, Height - 1);
  Fill (Rect, Col);
end;

procedure TCanvas.Fill (Rect : Ultibo.TRect; Col : LongWord);
var
  i, j : integer;
  px, py : PLongWord;
begin
  case ColourFormat of
    COLOR_FORMAT_ARGB32 : {32 bits per pixel Red/Green/Blue/Alpha (RGBA8888)}
      begin
        if Rect.left < 0 then Rect.left:= 0;
        if Rect.top < 0 then Rect.top := 0;
        if Rect.left >= Width then exit;
        if Rect.top >= Height then exit;
        if Rect.right >= Width then Rect.right := width - 1;
        if Rect.bottom >= Height then Rect.bottom := height - 1;
        if Rect.left >= Rect.right then exit;
        if Rect.top >= Rect.bottom then exit;
        for j := Rect.top to Rect.bottom do
          begin
            py := GetScanline (j);
            px := @py[Rect.left];
            for i := Rect.left to Rect.right do
              begin       // 000000ff blue   0000ff00 green    00ff0000 red
                px^ := Col;
                Inc (px);
              end;
          end;
      end;
    end;
end;

function TCanvas.GetScanLine (no: integer) : PLongWord;
begin
  LongWord (Result) := LongWord (Buffer) + (no * Width * SizeOf (LongWord));
end;

procedure TCanvas.Flush (FrameBuff : PFrameBufferDevice; x, y : integer);
begin
  FramebufferDevicePutRect (FrameBuff, x, y, Buffer, Width, Height, 0, FRAMEBUFFER_TRANSFER_DMA);
end;

procedure TCanvas.Flush (FrameBuff: PFrameBufferDevice);
begin
  FramebufferDevicePutRect (FrameBuff, Left, Top, Buffer, Width, Height, 0, FRAMEBUFFER_TRANSFER_DMA);
end;

procedure TCanvas.Assign (anOther: TCanvas);
begin
  if (anOther.Width <> Width) or (anOther.Height <> Height) or (anOther.ColourFormat <> ColourFormat) then
    SetSize (anOther.Width, anOther.Height, anOther.ColourFormat);
  Move (anOther.Buffer[0], Buffer[0], BufferSize);
end;

procedure TCanvas.DrawCanvas (aCanvas : TCanvas; x, y : integer);
var
  xm, ym, rw : integer;
  psx, psy, pdx, pdy : PLongWord;
begin
  xm := aCanvas.Width - 1;
  if xm + x >= Width then xm := Width - (x + 1);
  ym := aCanvas.Height - 1;
  if ym + y >= Height then ym := Height - (y + 1);
  if (x > Width) or (y > Height) then exit;
  psy := aCanvas.GetScanLine (0);
  pdy := GetScanLine (y);
  for rw := 0 to ym do
    begin
      psx := @psy[0];
      pdx := @pdy[rw];
      Move (psx^, pdx^, xm * 4);
      Inc (psy, aCanvas.Width);
      Inc (pdy, Width);
    end;
end;

procedure TCanvas.DrawImage (anImage : TImage32; x, y : integer; Alpha : byte = 255);
var
  xm, ym : integer;
  c : cardinal;
  rw, cl : integer;
  slx, sly : PImage32Value;
  a : byte;
  px, py : PLongWord;
begin
  if anImage = nil then exit;
  xm := x + anImage.width - 1;
  if xm >= width then xm := width - 1;
  ym := y + anImage.height - 1;
  if ym >= height then ym := height - 1;
  if (y > height) or (x > width) then exit;
  sly := anImage.GetScanline (0);
  py := GetScanline (y);
  for rw := 0 to ym - y do
    begin
      slx := @sly[0];
      px := @py[x];
      for cl := 0 to xm - x do
        begin
          a := (slx^.A * Alpha) div $100;
          c := ((GetRValue (px^) * (255 - a)) + slx^.R * a) div $100;
          c := c shl 8;
          c := c + ((GetGValue (px^) * (255 - a)) + slx^.G * a) div $100;
          c := c shl 8;
          c := c + ((GetBValue (px^) * (255 - a)) + slx^.B *  a) div $100;
          px^ := c;
          Inc (slx);
          Inc (px);
        end;
      Inc (sly, anImage.Width);
      Inc (py, Width);
    end;
end;

procedure TCanvas.DrawImage (anImage: TImage32; x, y, w, h : integer; Alpha : byte = 255);
var
  fi : TImage32;
begin
  if anImage = nil then exit;
  if (h = anImage.Height) and (w = anImage.Width) then
    DrawImage (anImage, x, y, Alpha)
  else
    begin
      fi := TImage32.Create (w, h);
      ReSize (fi, anImage);
      DrawImage (fi, x, y, Alpha);
      fi.free;
    end;
end;

constructor TCanvas.Create;
var
  res : integer;
begin
  Width := 0;
  Height := 0;
  Left := 0;
  Top := 0;
  Buffer := nil;
  ColourFormat := COLOR_FORMAT_UNKNOWN;
  if FTLib = nil then
    begin
      res := FT_Init_FreeType (FTLib);
      if res <> 0 then Log ('FTLib failed to Initialise.');
    end;
end;

destructor TCanvas.Destroy;
begin
  if Buffer <> nil then FreeMem (Buffer);
  inherited;
end;

function TextExtents (Text, Font : string; FontSize : integer) : FT_Vector; overload;
var
  anInfo : TFontInfo;
  fn : string;
begin
   if ExtractFileExt (Font) = '' then
    fn := Font + '.ttf'
  else
    fn := Font;
  anInfo := GetFontByName (fn, true);
  Result := TextExtents (Text, anInfo, FontSize);
end;

function TextExtents (Text : string; Font : TFontInfo; FontSize : integer) : FT_Vector; overload;
var
  err : integer;
  aFace : PFT_Face;
  i: integer;
  kerning : boolean;
  glyph_index,
  prev : cardinal;
  delta : FT_Vector;
  CharCode : cardinal;
  FirstByte, UTF8Bytes : byte;
begin
  Result.x := 0;
  Result.y := 0;
  delta.x := 0;
  delta.y := 0;
  if not Assigned (FTLib) then exit;
  aFace := nil;
  if Font = nil then exit;
  err := FT_New_Memory_Face (FTLIB, Font.Stream.Memory, Font.Stream.Size, 0, aFace);
  if err = 0 then  // if font face loaded ok
    begin
      err := FT_Set_Char_Size (aFace,                   // handle to face object
             0,                                         // char_width in 1/64th of points - Same as height
             FontSize * 64,                                   // char_height in 1/64th of points
             DPI,                                       // horizontal device resolution
             0);                                        // vertical device resolution
      if err = 0 then
        begin
          prev := 0;    // no previous char
          kerning := FT_HAS_KERNING (aFace);
          i := 1;
          while i <= length (Text) do
            begin
              FirstByte := byte (Text[1]);
              UTF8Bytes := 1;
              if FirstByte >= $80 then //  110xxxxx 10xxxxxx
                UTF8Bytes := UTF8Bytes + 1;
              if FirstByte >= $E0 then //  1110xxxx 10xxxxxx 10xxxxxx
                UTF8Bytes := UTF8Bytes + 1;
              if FirstByte >= $F0 then //  11110zzz 11zzxxxx 10xxxxxx 10xxxxxx
                UTF8Bytes := UTF8Bytes + 1;
              CharCode := 0;
              if i + (UTF8Bytes - 1) <= length (Text) then
                case UTF8Bytes of
                  1 : CharCode := cardinal (Text[i]);                              // 1Byte
                  2 : CharCode := (cardinal (Text[i]) and $1F ) * $40 +            // 000xxxxx
                                  (cardinal (Text[i + 1]) and $3F);                // 00xxxxxx
                  3 : CharCode := (cardinal (Text[i]) and $0F) * $1000 +           // 0000xxxx
                                  (cardinal (Text[i + 1]) and $3F) * $40 +         // 00xxxxxx
                                  (cardinal (Text[i + 2]) and $3F);                // 00xxxxxx
                  4 : CharCode := (cardinal (Text[i]) and $07) * $4000 +           // 0000xxxx
                                  (cardinal (Text[i + 1]) and $0F) * $1000 +       // 0000xxxx
                                  (cardinal (Text[i + 2]) and $3F) * $40 +         // 00xxxxxx
                                  (cardinal (Text[i + 3]) and $3F);                // 00xxxxxx
                  end;
              i := i + UTF8Bytes;
              if CharCode <> 0 then
                begin
                  glyph_index := FT_Get_Char_Index (aFace, CharCode);
                  if kerning and (prev <> 0) and (glyph_index <> 0) then
                    begin
                      FT_Get_Kerning (aFace, prev, glyph_index, FT_KERNING_DEFAULT, &delta);
                      Result.x := Result.x + delta.x;
                    end;
                  err := FT_Load_Glyph (aFace, glyph_index, FT_LOAD_NO_BITMAP);
                  if err > 0 then continue;                // ignore errors
                  Result.x := Result.x + aFace^.glyph^.advance.x;
                  if aFace^.glyph^.metrics.height > Result.y then Result.y := aFace^.glyph^.metrics.height;
                  prev := glyph_index;
                end;
            end;

        end;
      FT_Done_Face (aFace);
    end;
  Result.x := Result.x div 64;
  Result.y := Result.y div 64;
end;

procedure CollectImages;
var
  sr : TSearchRec;
  err : integer;
  im : TImage32;
  i : integer;
  f : TFileStream;
  ext : string;
begin
  if Images = nil then exit;
  Images.Clear;
  err := FindFirst ('*.*', faArchive, sr);
  while err = 0 do
    begin
      ext := LowerCase (ExtractFileExt (sr.Name));
      if (sr.Name = 'png') or (sr.Name = 'bmp') or (sr.Name = 'jpg') then
        begin
          if Images.GetImage (sr.Name) = nil then // does not exist
            begin
              im := TImage32.Create (0, 0);
              if im.LoadFromFile (sr.Name) then
                Images.Add (sr.Name, im)
              else
                im.Free;
            end;
        end;
      err := FindNext (sr);
    end;
  FindClose (sr);
end;

initialization

  Images := TImageLib.Create;

finalization

  Images.Clear;
  Images.Free;

end.

end.

