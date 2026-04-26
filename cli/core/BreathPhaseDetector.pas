unit BreathPhaseDetector;

{$mode objfpc}{$H+}

interface

uses
    SysUtils;

type
    TBreathPhaseType = (BREATH_PHASE_NONE,
        BREATH_PHASE_INHALE,
        BREATH_PHASE_EXHALE);

    {***************************************************************************
     * TBreathPhaseEvent
     ***************************************************************************}
    TBreathPhaseEvent = record
        HrValue                 : Integer;
        Phase                   : TBreathPhaseType;
        RawRrMs                 : Double;
        DeltaMs                 : Double;
        SmoothRrMs              : Double;
        SampleIndex             : Int64;
    end;

    {***************************************************************************
     * TBreathPhaseDetector
     ***************************************************************************}
    TBreathPhaseDetector = class
private
    FmaxValidRrMs           : Double;
    FminValidRrMs           : Double;
    FrawCount                : Integer;
    FsampleCount             : Int64;
    FlastPhase               : TBreathPhaseType;
    FminDeltaMs              : Double;
    FrawWindow               : array[0..4] of Double;

private
    procedure   appendRawSample(aRrMs: Double);
    function    detectPhase(aHrValue: Integer;
        out aEvent: TBreathPhaseEvent): Boolean;

public
    constructor Create;
    destructor  Destroy; override;

    function    addSample(aHrValue: Integer;
        aRrMs: Double; out aEvent: TBreathPhaseEvent): Boolean;
    procedure   reset();

public // property
    property MinDeltaMs: Double read FminDeltaMs write FminDeltaMs;
    property MinValidRrMs: Double read FminValidRrMs write FminValidRrMs;
    property MaxValidRrMs: Double read FmaxValidRrMs write FmaxValidRrMs;
    end;

function    breathPhaseToText(aPhase: TBreathPhaseType): string;
function    breathExtremumToText(aPhase: TBreathPhaseType): string;

implementation

const
    BREATH_WINDOW_SIZE = 5;
    DEFAULT_MIN_DELTA_MS = 3.0;
    DEFAULT_MIN_VALID_RR_MS = 300.0;
    DEFAULT_MAX_VALID_RR_MS = 1300.0;

{*******************************************************************************
* breathPhaseToText
*******************************************************************************}
function breathPhaseToText(aPhase: TBreathPhaseType): string;
begin
    case aPhase of
        BREATH_PHASE_INHALE:
            Result := 'inhale';
        BREATH_PHASE_EXHALE:
            Result := 'exhale';
    else
        Result := '';
    end;
end;

{*******************************************************************************
* breathExtremumToText
*******************************************************************************}
function breathExtremumToText(aPhase: TBreathPhaseType): string;
begin
    case aPhase of
        BREATH_PHASE_INHALE:
            Result := 'max';
        BREATH_PHASE_EXHALE:
            Result := 'min';
    else
        Result := '';
    end;
end;

{*******************************************************************************
* Create
*******************************************************************************}
constructor TBreathPhaseDetector.Create;
begin
    inherited Create;
    FminDeltaMs := DEFAULT_MIN_DELTA_MS;
    FminValidRrMs := DEFAULT_MIN_VALID_RR_MS;
    FmaxValidRrMs := DEFAULT_MAX_VALID_RR_MS;
    reset();
end;

{*******************************************************************************
* Destroy
*******************************************************************************}
destructor TBreathPhaseDetector.Destroy;
begin
    inherited Destroy;
end;

{*******************************************************************************
* reset
*******************************************************************************}
procedure TBreathPhaseDetector.reset();
begin
    FrawCount := 0;
    FsampleCount := 0;
    FlastPhase := BREATH_PHASE_NONE;
    FillChar(FrawWindow, SizeOf(FrawWindow), 0);
end;

{*******************************************************************************
* appendRawSample
*******************************************************************************}
procedure TBreathPhaseDetector.appendRawSample(aRrMs: Double);
var
    i: Integer;
begin
    if FrawCount < BREATH_WINDOW_SIZE then
    begin
        FrawWindow[FrawCount] := aRrMs;
        Inc(FrawCount);
        Exit;
    end;

    for i := 0 to BREATH_WINDOW_SIZE - 2 do
        FrawWindow[i] := FrawWindow[i + 1];
    FrawWindow[BREATH_WINDOW_SIZE - 1] := aRrMs;
end;

{*******************************************************************************
* detectPhase
*******************************************************************************}
function TBreathPhaseDetector.detectPhase(aHrValue: Integer;
    out aEvent: TBreathPhaseEvent): Boolean;
var
    prom: Double;
    phase: TBreathPhaseType;
    delta: Double;
    leftDelta: Double;
    midSmooth: Double;
    leftSmooth: Double;
    rightDelta: Double;
    rightSmooth: Double;
begin
    Result := False;
    FillChar(aEvent, SizeOf(aEvent), 0);
    aEvent.Phase := BREATH_PHASE_NONE;

    if FrawCount < BREATH_WINDOW_SIZE then
        Exit;

    leftSmooth := (FrawWindow[0] + FrawWindow[1] + FrawWindow[2]) / 3.0;
    midSmooth := (FrawWindow[1] + FrawWindow[2] + FrawWindow[3]) / 3.0;
    rightSmooth := (FrawWindow[2] + FrawWindow[3] + FrawWindow[4]) / 3.0;

    phase := BREATH_PHASE_NONE;
    if (midSmooth <= leftSmooth) and (midSmooth <= rightSmooth) and
        ((midSmooth < leftSmooth) or (midSmooth < rightSmooth)) then
        phase := BREATH_PHASE_EXHALE
    else if (midSmooth >= leftSmooth) and (midSmooth >= rightSmooth) and
        ((midSmooth > leftSmooth) or (midSmooth > rightSmooth)) then
        phase := BREATH_PHASE_INHALE;

    if phase = BREATH_PHASE_NONE then
        Exit;

    leftDelta := Abs(midSmooth - leftSmooth);
    rightDelta := Abs(midSmooth - rightSmooth);
    if leftDelta < rightDelta then
        delta := leftDelta
    else
        delta := rightDelta;

    prom := Abs(midSmooth - ((leftSmooth + rightSmooth) / 2.0));
    if prom > delta then
        delta := prom;

    if delta < FminDeltaMs then
        Exit;

    if phase = FlastPhase then
        Exit;

    aEvent.HrValue := aHrValue;
    aEvent.Phase := phase;
    aEvent.RawRrMs := FrawWindow[2];
    aEvent.DeltaMs := delta;
    aEvent.SmoothRrMs := midSmooth;
    // FsampleCount was already incremented in addSample, so the centre of the
    // 3-point smooth window (FrawWindow[2]) corresponds to sample #(count-3).
    aEvent.SampleIndex := FsampleCount - 3;
    FlastPhase := phase;
    Result := True;
end;

{*******************************************************************************
* addSample
*******************************************************************************}
function TBreathPhaseDetector.addSample(aHrValue: Integer;
    aRrMs: Double; out aEvent: TBreathPhaseEvent): Boolean;
begin
    FillChar(aEvent, SizeOf(aEvent), 0);
    aEvent.Phase := BREATH_PHASE_NONE;

    if (aRrMs < FminValidRrMs) or (aRrMs > FmaxValidRrMs) then
    begin
        Result := False;
        Exit;
    end;

    Inc(FsampleCount);
    appendRawSample(aRrMs);
    Result := detectPhase(aHrValue, aEvent);
end;

end.