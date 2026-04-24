unit BodyMonitorControlProtocol;

{$mode objfpc}{$H+}

interface

uses
    SysUtils,
    fpjson,
    jsonparser,
    LogCore;

type
    TStdioCmdType = (
        sctUnknown,
        sctConfigure,
        sctListDevices,
        sctStart,
        sctPing,
        sctStop,
        sctSetParam,
        sctQuit
    );

    TStdioCommand = record
        CmdType     : TStdioCmdType;
        Params      : TStringArray;   // used by sctConfigure
        ParamKey    : string;         // used by sctSetParam
        ParamValue  : string;         // used by sctSetParam
    end;

{*******************************************************************************
* parseStdioCommand
*   Parses a JSONL line from stdin into a TStdioCommand.
*   Returns True on success. Returns False with aCmd.CmdType = sctUnknown if
*   the line is not a recognized command.
*******************************************************************************}
function parseStdioCommand(const aLine: string; out aCmd: TStdioCommand): Boolean;

{*******************************************************************************
* makeStdioAck
*   Builds a {"event":"stdio_ack","cmd":"...","ok":true/false[,"error":"..."]}
*   JSON line for stdout acknowledgment.
*******************************************************************************}
function makeStdioAck(const aCmdName: string; aOk: Boolean;
    const aError: string = ''): string;

implementation

{*******************************************************************************
* parseStdioCommand
*******************************************************************************}
function parseStdioCommand(const aLine: string; out aCmd: TStdioCommand): Boolean;
var
    data: TJSONData;
    obj: TJSONObject;
    arr: TJSONArray;
    cmdStr: string;
    i: Integer;
begin
    Result := False;
    aCmd.CmdType := sctUnknown;
    SetLength(aCmd.Params, 0);
    aCmd.ParamKey := '';
    aCmd.ParamValue := '';

    if Trim(aLine) = '' then
        Exit;

    data := nil;
    try
        try
            data := GetJSON(aLine);
        except
            Exit;
        end;

        if not (data is TJSONObject) then
            Exit;

        obj := TJSONObject(data);

        if obj.IndexOfName('cmd') < 0 then
            Exit;

        cmdStr := LowerCase(obj.Strings['cmd']);

        if cmdStr = 'configure' then
        begin
            aCmd.CmdType := sctConfigure;
            if obj.IndexOfName('params') >= 0 then
            begin
                arr := obj.Arrays['params'];
                SetLength(aCmd.Params, arr.Count);
                for i := 0 to arr.Count - 1 do
                    aCmd.Params[i] := arr.Strings[i];
            end;
            Result := True;
        end
        else if cmdStr = 'list_devices' then
        begin
            aCmd.CmdType := sctListDevices;
            Result := True;
        end
        else if cmdStr = 'start' then
        begin
            aCmd.CmdType := sctStart;
            Result := True;
        end
        else if cmdStr = 'ping' then
        begin
            aCmd.CmdType := sctPing;
            Result := True;
        end
        else if cmdStr = 'stop' then
        begin
            aCmd.CmdType := sctStop;
            Result := True;
        end
        else if cmdStr = 'set_param' then
        begin
            aCmd.CmdType := sctSetParam;
            if (obj.IndexOfName('key') >= 0) and (obj.IndexOfName('value') >= 0) then
            begin
                aCmd.ParamKey := obj.Strings['key'];
                aCmd.ParamValue := obj.Strings['value'];
                Result := True;
            end;
        end
        else if cmdStr = 'quit' then
        begin
            aCmd.CmdType := sctQuit;
            Result := True;
        end;
    finally
        FreeAndNil(data);
    end;
end;

{*******************************************************************************
* makeStdioAck
*******************************************************************************}
function makeStdioAck(const aCmdName: string; aOk: Boolean;
    const aError: string = ''): string;
begin
    if aOk then
        Result := '{"event":"stdio_ack","cmd":"' + jsonEscape(aCmdName) + '","ok":true}'
    else
        Result := '{"event":"stdio_ack","cmd":"' + jsonEscape(aCmdName) +
            '","ok":false,"error":"' + jsonEscape(aError) + '"}';
end;

end.