program CanvasTest;

{$mode delphi}
{$notes off}
{$hints off}
{$H+}

uses
  RaspberryPi3,
  GlobalConfig,
  GlobalConst,
  GlobalTypes,
  Platform,
  Threads,
  SysUtils,
  Classes,
  freetypeh,
  uFontInfo,
  FPReadPNG,
  uLog,
  FPImage,
  FrameBuffer,
  uCanvas,
  Logging,
  Services,
  SyncObjs,
  uTFTP, Winsock2,
  Ultibo;

type
  TTimerEvent = procedure;

  { TTimerThread }

  TTimerThread = class (TThread)
    FInterval : integer;
    FEvent : TEvent;
    FProc : TTimerEvent;
    procedure Execute; override;
    constructor Create (anInterval : Cardinal; anEvent : TTimerEvent);
    destructor Destroy; override;
  end;

var
  ch : char;
  i : integer;
  im : TImage32;
  DefFrameBuff : PFrameBufferDevice;
  FrameProps : TFrameBufferProperties;
  w, h : LongWord;
  aCanvas : TCanvas;
  sz : integer;
  SysLogger : PLoggingDevice;
  Timer : TTimerThread;
  SeqNo : integer;
  SeqCount : integer;
  SeqX, SeqY : integer;
  IPAddress : string;

procedure WaitForSDDrive;
begin
  while not DirectoryExists ('C:\') do sleep (500);
end;

function WaitForIPComplete : string;
var
  TCP : TWinsock2TCPClient;
begin
  TCP := TWinsock2TCPClient.Create;
  Result := TCP.LocalAddress;
  if (Result = '') or (Result = '0.0.0.0') or (Result = '255.255.255.255') then
    begin
      while (Result = '') or (Result = '0.0.0.0') or (Result = '255.255.255.255') do
        begin
          Sleep (1000);
          Result := TCP.LocalAddress;
        end;
    end;
  TCP.Free;
end;

function display_string (s : string) : string;
var
  i : integer;
begin
  Result := '';
  for i := 1 to length (s) do
    if s[i] in [' ' .. '~'] then
      Result := Result + s[i]
    else
      Result := Result + '<' + ord (s[i]).ToString + '>';
end;

procedure LogEr (const s : string);
begin
  LoggingOutput (s);
end;

procedure TimerEvent;
var
  x, y : integer;
  sz : FT_Vector;

  procedure FadeOut (Text : string; Font : string; Size : integer);
  begin
    sz := TextExtents (Text, Font, Size);
    x := (aCanvas.Width - sz.x) div 2;
    sz := TextExtents ('Mg', Font, Size);
    y := (aCanvas.Height - sz.y) div 2 + sz.y;
    aCanvas.Fill (COLOR_BLACK);
    if SeqCount = 0 then
      begin
        SeqCount := 25;
        SeqX := 255;
      end
    else
      begin
        SeqX := SeqX - 255 div 20;
        if SeqX < 5 then
          begin
            SeqX := 0;
            SeqCount := 0;
            aCanvas.Flush (DefFrameBuff);
          end;
      end;
    if SeqCount > 0 then aCanvas.DrawText (x, y, Text, Font, Size, COLOR_WHITE, SeqX);
    aCanvas.Flush (DefFrameBuff);
  end;

  procedure FadeIn (Text : string; Font : string; Size : integer);
  begin
    sz := TextExtents (Text, Font, Size);
    x := (aCanvas.Width - sz.x) div 2;
    sz := TextExtents ('Mg', Font, Size);
    y := (aCanvas.Height - sz.y) div 2 + sz.y;
    aCanvas.Fill (COLOR_BLACK);
    if SeqCount = 0 then
      begin
        SeqCount := 25;
        SeqX := 0;
      end
    else
      begin
        SeqX := SeqX + 255 div 20;
        if SeqX > 254 then
          begin
            SeqX := 255;
            SeqCount := 0;
          end;
      end;
    aCanvas.DrawText (x, y, Text, Font, Size, COLOR_WHITE, SeqX);
    aCanvas.Flush (DefFrameBuff);
  end;

  procedure FadeOutImage (Name : string);
  var
    im : TImage32;
  begin
    im := Images.GetPng (Name);
    if im = nil then exit;
    x := (aCanvas.Width - im.Width) div 2;
    y := (aCanvas.Height - im.Height) div 2;
    aCanvas.Fill (COLOR_BLACK);
    if SeqCount = 0 then
      begin
        SeqCount := 25;
        SeqX := 255;
      end
    else
      begin
        SeqX := SeqX - 255 div 20;
        if SeqX < 5 then
          begin
            SeqX := 0;
            SeqCount := 0;
            aCanvas.Flush (DefFrameBuff);
          end;
      end;
    if SeqCount > 0 then
      begin
        aCanvas.DrawImage (im, x, y, SeqX);
      end;
    aCanvas.Flush (DefFrameBuff);
  end;

  procedure FadeInImage (Name : string);
  var
    im : TImage32;
  begin
    im := Images.GetPng (Name);
    if im = nil then exit;
    x := (aCanvas.Width - im.Width) div 2;
    y := (aCanvas.Height - im.Height) div 2;
    aCanvas.Fill (COLOR_BLACK);
    if SeqCount = 0 then
      begin
        SeqCount := 25;
        SeqX := 0;
      end
    else
      begin
        SeqX := SeqX + 255 div 20;
        if SeqX > 254 then
          begin
            SeqX := 255;
            SeqCount := 0;
          end;
      end;
    aCanvas.DrawImage (im, x, y, SeqX);
    aCanvas.Flush (DefFrameBuff);
  end;

  procedure Delay (aCount : integer);
  begin
    if SeqCount = 0 then SeqCount := aCount;
  end;

begin
 // LogEr ('No ' + IntToStr (SeqNo) + ' Count ' + IntToStr (SeqCount));
  case SeqNo of
     1 : FadeIn ('Welcome', 'Arial', 150); // welcome in
     2 : Delay (20); // wait
     3 : FadeOut ('Welcome', 'Arial', 150); // welcome out
     4 : Delay (10); // wait
     5 : FadeIn ('to', 'Arial', 150); // to in
     6 : Delay (20); // wait
     7 : FadeOut ('to', 'Arial', 150); // to out
     8 : Delay (10); // wait
     9 : FadeIn ('Canvas...', 'Arial', 150); // Canvas in
    10 : Delay (20); // wait
    11 : FadeOut ('Canvas...', 'Arial', 150); // Canvas out
    12 : Delay (10); // wait
    13 : FadeInImage ('ultibo-com.png');
    14 : Delay (20); // wait
    15 : FadeOutImage ('ultibo-com.png');
    16 : Delay (20); // wait

     else
       begin
         SeqNo := 0;
         SeqCount := 0;
       end;
    end;
  if SeqCount > 0 then SeqCount := SeqCount - 1;
  if SeqCount = 0 then SeqNo := SeqNo + 1;
end;

procedure TTimerThread.Execute;
var
  res : TWaitResult;
begin
  while not Terminated do
    begin
      FEvent.ResetEvent;
      res := FEvent.WaitFor (FInterval);
      if ((ord (res) = ERROR_WAIT_TIMEOUT) or (res = wrTimeout)) and Assigned (FProc) then
        FProc;
    end;
end;

constructor TTimerThread.Create (anInterval : Cardinal; anEvent : TTimerEvent);
begin
  inherited Create (true);
  FInterval := anInterval;
  FProc := anEvent;
  FreeOnTerminate := true;
  FEvent := TEvent.Create (nil, true, false, '');
end;

destructor TTimerThread.Destroy;
begin
  FEvent.Free;
  inherited Destroy;
end;

begin
  SysLogger := LoggingDeviceFindByType (LOGGING_TYPE_SYSLOG);
 // SysLogLoggingSetTarget (SysLogger, '255.255.255.255');
  SysLogLoggingSetTarget (SysLogger, '192.168.0.100');
  LoggingDeviceSetDefault (SysLogger);
  SetLogProc (@LogEr);

  DefFrameBuff := FramebufferDeviceGetDefault;
  FramebufferDeviceGetProperties (DefFrameBuff, @FrameProps);
  w := FrameProps.PhysicalWidth;
  h := FrameProps.PhysicalHeight;
  aCanvas := TCanvas.Create;
  aCanvas.SetSize (w, h, COLOR_FORMAT_ARGB32);
  aCanvas.Fill (COLOR_BLACK);
  aCanvas.Flush (DefFrameBuff);

  WaitForSDDrive;
  IPAddress := WaitForIPComplete;

  ch := #0;
  CollectFonts (true);
  try
    im := TImage32.Create (0, 0);
    im.LoadFromFile ('ultibo-com.png');
    i := Images.Add ('ultibo-com.png', im);
    Images[i].DefImage := true;
  except
    on e:exception do LogEr (e.Message);
  end;

{  if Images.Count > 0 then
    for i := 0 to Images.Count - 1 do
      LogEr (TLibImage (Images[i]).Name);  }
  SeqNo := 1;
  SeqCount := 0;
  SeqX := 0;
  SeqY := 0;

  Timer := TTimerThread.Create (150, TimerEvent);
  Timer.Start;

  while true do
    begin
      if ConsoleReadChar (ch, nil) then
        case (ch) of
         'A', 'a' :
            begin
              aCanvas.Flush (DefFrameBuff);
            end
          else
            begin
            end;
        end;
    end;
  ThreadHalt (0);
end.

