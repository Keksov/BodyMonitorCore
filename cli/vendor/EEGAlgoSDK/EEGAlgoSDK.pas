unit EEGAlgoSDK;

{$mode objfpc}{$H+}
{$PACKRECORDS C}

interface

const
    NS_TRUE = 1;
    NS_FALSE = 0;

    NSK_ALGO_DATA_TYPE_EEG = $01;
    NSK_ALGO_DATA_TYPE_ATT = $02;
    NSK_ALGO_DATA_TYPE_MED = $03;
    NSK_ALGO_DATA_TYPE_PQ = $04;
    NSK_ALGO_DATA_TYPE_BULK_EEG = $05;

    NSK_ALGO_TYPE_ATT = $00000100;
    NSK_ALGO_TYPE_MED = $00000200;
    NSK_ALGO_TYPE_BLINK = $00000400;
    NSK_ALGO_TYPE_BP = $00004000;

    NSK_ALGO_CB_TYPE_STATE = $01000000;
    NSK_ALGO_CB_TYPE_SIGNAL_LEVEL = $02000000;
    NSK_ALGO_CB_TYPE_ALGO = $04000000;

    NSK_ALGO_STATE_MASK = $FF00;
    NSK_ALGO_REASON_MASK = $00FF;

    NSK_ALGO_STATE_INITED = $0100;
    NSK_ALGO_STATE_RUNNING = $0200;
    NSK_ALGO_STATE_COLLECTING_BASELINE_DATA = $0300;
    NSK_ALGO_STATE_STOP = $0400;
    NSK_ALGO_STATE_PAUSE = $0500;
    NSK_ALGO_STATE_UNINTIED = $0600;
    NSK_ALGO_STATE_ANALYSING_BULK_DATA = $0800;
    NSK_ALGO_STATE_RUNNING_DEMO = $1000;

    NSK_ALGO_REASON_CONFIG_CHANGED = $0001;
    NSK_ALGO_REASON_USER_PROFILE_CHANGED = $0002;
    NSK_ALGO_REASON_CB_CHANGED = $0003;
    NSK_ALGO_REASON_BY_USER = $0004;
    NSK_ALGO_REASON_BASELINE_EXPIRED = $0005;
    NSK_ALGO_REASON_NO_BASELINE = $0006;
    NSK_ALGO_REASON_SIGNAL_QUALITY = $0007;

    NSK_ALGO_SQ_GOOD = 0;
    NSK_ALGO_SQ_MEDIUM = 1;
    NSK_ALGO_SQ_POOR = 2;
    NSK_ALGO_SQ_NOT_DETECTED = 3;

    NSK_ALGO_RET_SUCCESS = 0;

type
    TNSAlgoIndex = Single;

    TNSAlgoBpIndex = record
        deltaPower: TNSAlgoIndex;
        thetaPower: TNSAlgoIndex;
        alphaPower: TNSAlgoIndex;
        betaPower: TNSAlgoIndex;
        gammaPower: TNSAlgoIndex;
    end;

    TNSKAlgoIndexValueGroup = record
        case Integer of
            0: (attIndex: TNSAlgoIndex);
            1: (medIndex: TNSAlgoIndex);
            2: (eyeBlinkStrength: TNSAlgoIndex);
            3: (bpIndex: TNSAlgoBpIndex);
    end;

    TNSKAlgoIndex = record
        algoType: LongInt;
        value: TNSKAlgoIndexValueGroup;
        timeSpent: LongInt;
    end;

    TNSKAlgoCbParamData = record
        case Integer of
            0: (state: LongInt);
            1: (sq: LongInt);
            2: (algoIndex: TNSKAlgoIndex);
    end;

    TNSKAlgoCbParam = record
        cbType: LongInt;
        param: TNSKAlgoCbParamData;
        userData: Pointer;
    end;

    TNskAlgoCallback = procedure(aParam: TNSKAlgoCbParam); cdecl;

function    NSK_ALGO_Init(aType: LongInt; const aDataPath: PAnsiChar): LongInt; cdecl; external 'AlgoSdkDll64.dll';
function    NSK_ALGO_Uninit(): LongInt; cdecl; external 'AlgoSdkDll64.dll';
function    NSK_ALGO_RegisterCallback(aCbFunc: TNskAlgoCallback; aUserData: Pointer): LongInt; cdecl; external 'AlgoSdkDll64.dll';
function    NSK_ALGO_SdkVersion(): PAnsiChar; cdecl; external 'AlgoSdkDll64.dll';
function    NSK_ALGO_AlgoVersion(aType: LongInt): PAnsiChar; cdecl; external 'AlgoSdkDll64.dll';
function    NSK_ALGO_Start(aBaseline: Byte): LongInt; cdecl; external 'AlgoSdkDll64.dll';
function    NSK_ALGO_Pause(): LongInt; cdecl; external 'AlgoSdkDll64.dll';
function    NSK_ALGO_Stop(): LongInt; cdecl; external 'AlgoSdkDll64.dll';
function    NSK_ALGO_DataStream(aType: LongInt; aData: PSmallInt; aDataLength: LongInt): LongInt; cdecl; external 'AlgoSdkDll64.dll';

function    algoStateToText(aStateValue: LongInt): string;
function    algoReasonToText(aReasonValue: LongInt): string;
function    algoSignalQualityToText(aSignalQuality: LongInt): string;

implementation

uses
    SysUtils;

{*******************************************************************************
* algoStateToText
*******************************************************************************}
function algoStateToText(aStateValue: LongInt): string;
begin
    case aStateValue of
        NSK_ALGO_STATE_INITED: Result := 'Inited';
        NSK_ALGO_STATE_RUNNING: Result := 'Running';
        NSK_ALGO_STATE_COLLECTING_BASELINE_DATA: Result := 'Collecting baseline';
        NSK_ALGO_STATE_STOP: Result := 'Stopped';
        NSK_ALGO_STATE_PAUSE: Result := 'Paused';
        NSK_ALGO_STATE_UNINTIED: Result := 'Uninited';
        NSK_ALGO_STATE_ANALYSING_BULK_DATA: Result := 'Analysing bulk data';
        NSK_ALGO_STATE_RUNNING_DEMO: Result := 'Running demo';
        else Result := Format('Unknown state (%d)', [aStateValue]);
    end;
end;

{*******************************************************************************
* algoReasonToText
*******************************************************************************}
function algoReasonToText(aReasonValue: LongInt): string;
begin
    case aReasonValue of
        NSK_ALGO_REASON_CONFIG_CHANGED: Result := 'Config changed';
        NSK_ALGO_REASON_USER_PROFILE_CHANGED: Result := 'User profile changed';
        NSK_ALGO_REASON_CB_CHANGED: Result := 'Callback changed';
        NSK_ALGO_REASON_BY_USER: Result := 'By user';
        NSK_ALGO_REASON_BASELINE_EXPIRED: Result := 'Baseline expired';
        NSK_ALGO_REASON_NO_BASELINE: Result := 'No baseline';
        NSK_ALGO_REASON_SIGNAL_QUALITY: Result := 'Signal quality';
        else Result := Format('Unknown reason (%d)', [aReasonValue]);
    end;
end;

{*******************************************************************************
* algoSignalQualityToText
*******************************************************************************}
function algoSignalQualityToText(aSignalQuality: LongInt): string;
begin
    case aSignalQuality of
        NSK_ALGO_SQ_GOOD: Result := 'Good';
        NSK_ALGO_SQ_MEDIUM: Result := 'Medium';
        NSK_ALGO_SQ_POOR: Result := 'Poor';
        NSK_ALGO_SQ_NOT_DETECTED: Result := 'Not detected';
        else Result := Format('Unknown quality (%d)', [aSignalQuality]);
    end;
end;

end.
