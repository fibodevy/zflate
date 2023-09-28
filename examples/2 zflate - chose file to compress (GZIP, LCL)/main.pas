unit main;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, EditBtn, StdCtrls;

type
  TForm1 = class(TForm)
    Button1: TButton;
    FileNameEdit1: TFileNameEdit;
    FileNameEdit2: TFileNameEdit;
    Label1: TLabel;
    Label2: TLabel;
    procedure Button1Click(Sender: TObject);
    procedure FormCreate(Sender: TObject);
  private

  public

  end;

var
  Form1: TForm1;

implementation

uses zflate;

{$R *.lfm}

procedure TForm1.Button1Click(Sender: TObject);
var
  ss: TStringStream;
  s: string;
begin
  if not FileExists(FileNameEdit1.FileName) then begin
    ShowMessage('Input file does not exists');
    exit;
  end;

  if FileExists(FileNameEdit2.FileName) then begin
    ShowMessage('Output file already exists');
    exit;
  end;

  ss := TStringStream.Create;
  ss.LoadFromFile(FileNameEdit1.FileName);

  // compress
  s := gzencode(ss.DataString, 9, ExtractFileName(FileNameEdit1.FileName));

  // save
  ss.Clear;
  ss.Write(s[1], length(s));

  ss.SaveToFile(FileNameEdit2.FileName);

  ShowMessage('Done!');
end;

procedure TForm1.FormCreate(Sender: TObject);
begin
  FileNameEdit1.FileName := Application.ExeName;
end;

end.

