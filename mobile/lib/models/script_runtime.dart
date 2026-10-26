/// Runtime state of a script execution session. Stored on [AppSession] so the
/// session pill, switcher, navigation badge, and the execution dock can all
/// render the same state without reaching into renderer internals.
enum ScriptSessionStatus {
  connecting,
  running,
  waitingForInput,
  cancelling,
  cancelled,
  completed,
  failed,
  disconnected,
}

class ScriptRuntimeState {
  final String scriptName;
  final ScriptSessionStatus status;
  final String? currentStep;
  final int currentStepNumber;
  final int stepCount;
  final int? progressPercent;
  final String progressMessage;
  final String? error;
  final int? exitCode;

  const ScriptRuntimeState({
    required this.scriptName,
    required this.status,
    this.currentStep,
    this.currentStepNumber = 0,
    this.stepCount = 0,
    this.progressPercent,
    this.progressMessage = '',
    this.error,
    this.exitCode,
  });

  factory ScriptRuntimeState.initial(String scriptName) => ScriptRuntimeState(
    scriptName: scriptName,
    status: ScriptSessionStatus.connecting,
  );

  bool get needsInput => status == ScriptSessionStatus.waitingForInput;

  bool get isTerminal =>
      status == ScriptSessionStatus.cancelled ||
      status == ScriptSessionStatus.completed ||
      status == ScriptSessionStatus.failed ||
      status == ScriptSessionStatus.disconnected;

  ScriptRuntimeState copyWith({
    String? scriptName,
    ScriptSessionStatus? status,
    String? currentStep,
    int? currentStepNumber,
    int? stepCount,
    int? progressPercent,
    String? progressMessage,
    String? error,
    int? exitCode,
    bool clearError = false,
    bool clearExitCode = false,
  }) {
    return ScriptRuntimeState(
      scriptName: scriptName ?? this.scriptName,
      status: status ?? this.status,
      currentStep: currentStep ?? this.currentStep,
      currentStepNumber: currentStepNumber ?? this.currentStepNumber,
      stepCount: stepCount ?? this.stepCount,
      progressPercent: progressPercent ?? this.progressPercent,
      progressMessage: progressMessage ?? this.progressMessage,
      error: clearError ? null : (error ?? this.error),
      exitCode: clearExitCode ? null : (exitCode ?? this.exitCode),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScriptRuntimeState &&
          scriptName == other.scriptName &&
          status == other.status &&
          currentStep == other.currentStep &&
          currentStepNumber == other.currentStepNumber &&
          stepCount == other.stepCount &&
          progressPercent == other.progressPercent &&
          progressMessage == other.progressMessage &&
          error == other.error &&
          exitCode == other.exitCode;

  @override
  int get hashCode => Object.hash(
    scriptName,
    status,
    currentStep,
    currentStepNumber,
    stepCount,
    progressPercent,
    progressMessage,
    error,
    exitCode,
  );
}
