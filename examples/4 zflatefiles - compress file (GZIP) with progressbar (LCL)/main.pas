unit main;

{$mode objfpc}{$H+}
{$modeswitch anonymousfunctions}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, EditBtn, StdCtrls,
  ComCtrls, Math;

type
  TForm1 = class(TForm)
    Button1: TButton;
    Button2: TButton;
    FileNameEdit1: TFileNameEdit;
    FileNameEdit2: TFileNameEdit;
    Label1: TLabel;
    Label2: TLabel;
    Label3: TLabel;
    ProgressBar1: TProgressBar;
    procedure Button1Click(Sender: TObject);
    procedure Button2Click(Sender: TObject);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FormCreate(Sender: TObject);
  private

  public

  end;

var
  Form1: TForm1;
  abort: boolean = false;

implementation

uses zflate, zflatefiles;

{$R *.lfm}

procedure TForm1.Button1Click(Sender: TObject);
begin
  if not FileExists(FileNameEdit1.FileName) then begin
    ShowMessage('Input file does not exists');
    exit;
  end;

  if FileExists(FileNameEdit2.FileName) then begin
    ShowMessage('Output file already exists');
    exit;
  end;

  Button1.Enabled := false;
  Button2.Enabled := true;

  abort := false;

  if gzencode_file(FileNameEdit1.FileName, FileNameEdit2.FileName, 9, ExtractFileName(FileNameEdit1.FileName), '',
    (function(position, totalsize, outputsize: dword): boolean
    var
      progress: double;
    begin
      progress := position/totalsize*100;

      Form1.ProgressBar1.Position := trunc(progress);
      Form1.Label3.Caption := (FloatToStrF(progress, ffFixed, 2, 2)+'%').Replace(',', '.');
      Application.ProcessMessages;

      result := not abort;
    end), 10000
  ) then
    ShowMessage('Done!')
  else begin
    if not (zlasterror = ZFLATE_EABORTED) then
      ShowMessage('Failed');
  end;

  Button1.Enabled := true;
  Button2.Enabled := false;
end;

procedure TForm1.Button2Click(Sender: TObject);
begin
  abort := true;
end;

procedure TForm1.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  abort := true;
end;

procedure TForm1.FormCreate(Sender: TObject);
begin
  //FileNameEdit1.FileName := Application.ExeName;
end;

end.

