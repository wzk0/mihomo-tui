/// Thin, lazily bound Win32 bindings (only used when running on Windows).
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

const int stdInputHandle = -10;
const int stdOutputHandle = -11;

// Console modes.
const int enableProcessedInput = 0x0001;
const int enableLineInput = 0x0002;
const int enableEchoInput = 0x0004;
const int enableWindowInput = 0x0008;
const int enableMouseInput = 0x0010;
const int enableInsertMode = 0x0020;
const int enableQuickEditMode = 0x0040;
const int enableExtendedFlags = 0x0080;
const int enableVirtualTerminalInput = 0x0200;

const int enableProcessedOutput = 0x0001;
const int enableWrapAtEolOutput = 0x0002;
const int enableVirtualTerminalProcessing = 0x0004;

// CreateProcess flags.
const int createNoWindow = 0x08000000;
const int createNewProcessGroup = 0x00000200;
const int detachedProcess = 0x00000008;

const int startfUseStdHandles = 0x00000100;

const int genericWrite = 0x40000000;
const int fileShareRead = 0x00000001;
const int fileShareWrite = 0x00000002;
const int openAlways = 4;
const int fileAppendData = 0x00000004;
const int fileAttributeNormal = 0x00000080;

const int processTerminate = 0x0001;
const int processQueryLimitedInformation = 0x1000;
const int stillActive = 259;

final class SecurityAttributes extends Struct {
  @Uint32()
  external int nLength;

  external Pointer<Void> lpSecurityDescriptor;

  @Int32()
  external int bInheritHandle;
}

final class StartupInfoW extends Struct {
  @Uint32()
  external int cb;

  external Pointer<Utf16> lpReserved;
  external Pointer<Utf16> lpDesktop;
  external Pointer<Utf16> lpTitle;

  @Uint32()
  external int dwX;
  @Uint32()
  external int dwY;
  @Uint32()
  external int dwXSize;
  @Uint32()
  external int dwYSize;
  @Uint32()
  external int dwXCountChars;
  @Uint32()
  external int dwYCountChars;
  @Uint32()
  external int dwFillAttribute;
  @Uint32()
  external int dwFlags;

  @Uint16()
  external int wShowWindow;
  @Uint16()
  external int cbReserved2;

  external Pointer<Uint8> lpReserved2;

  @IntPtr()
  external int hStdInput;

  @IntPtr()
  external int hStdOutput;

  @IntPtr()
  external int hStdError;
}

final class ProcessInformation extends Struct {
  @IntPtr()
  external int hProcess;

  @IntPtr()
  external int hThread;

  @Uint32()
  external int dwProcessId;

  @Uint32()
  external int dwThreadId;
}

class Win32 {
  Win32._(this._lib) {
    getStdHandle =
        _lib.lookupFunction<IntPtr Function(Int32), int Function(int)>(
            'GetStdHandle');
    setConsoleMode = _lib.lookupFunction<Int32 Function(IntPtr, Uint32),
        int Function(int, int)>('SetConsoleMode');
    getConsoleMode = _lib.lookupFunction<
        Int32 Function(IntPtr, Pointer<Uint32>),
        int Function(int, Pointer<Uint32>)>('GetConsoleMode');
    readConsoleInput = _lib.lookupFunction<
        Int32 Function(IntPtr, Pointer<Uint8>, Uint32, Pointer<Uint32>),
        int Function(int, Pointer<Uint8>, int, Pointer<Uint32>)>(
      'ReadConsoleInputW',
    );
    getNumberOfConsoleInputEvents = _lib.lookupFunction<
        Int32 Function(IntPtr, Pointer<Uint32>),
        int Function(int, Pointer<Uint32>)>('GetNumberOfConsoleInputEvents');
    getConsoleScreenBufferInfo = _lib.lookupFunction<
        Int32 Function(IntPtr, Pointer<Uint8>),
        int Function(int, Pointer<Uint8>)>('GetConsoleScreenBufferInfo');
    setConsoleOutputCP =
        _lib.lookupFunction<Int32 Function(Uint32), int Function(int)>(
      'SetConsoleOutputCP',
    );
    setConsoleCP =
        _lib.lookupFunction<Int32 Function(Uint32), int Function(int)>(
      'SetConsoleCP',
    );
    openProcess = _lib.lookupFunction<IntPtr Function(Uint32, Int32, Uint32),
        int Function(int, int, int)>('OpenProcess');
    getExitCodeProcess = _lib.lookupFunction<
        Int32 Function(IntPtr, Pointer<Uint32>),
        int Function(int, Pointer<Uint32>)>('GetExitCodeProcess');
    terminateProcess = _lib.lookupFunction<Int32 Function(IntPtr, Uint32),
        int Function(int, int)>('TerminateProcess');
    closeHandle =
        _lib.lookupFunction<Int32 Function(IntPtr), int Function(int)>(
      'CloseHandle',
    );
    createFile = _lib.lookupFunction<
        IntPtr Function(Pointer<Utf16>, Uint32, Uint32,
            Pointer<SecurityAttributes>, Uint32, Uint32, IntPtr),
        int Function(Pointer<Utf16>, int, int, Pointer<SecurityAttributes>, int,
            int, int)>('CreateFileW');
    createProcess = _lib.lookupFunction<
        Int32 Function(
            Pointer<Utf16>,
            Pointer<Utf16>,
            Pointer<SecurityAttributes>,
            Pointer<SecurityAttributes>,
            Int32,
            Uint32,
            Pointer<Void>,
            Pointer<Utf16>,
            Pointer<StartupInfoW>,
            Pointer<ProcessInformation>),
        int Function(
            Pointer<Utf16>,
            Pointer<Utf16>,
            Pointer<SecurityAttributes>,
            Pointer<SecurityAttributes>,
            int,
            int,
            Pointer<Void>,
            Pointer<Utf16>,
            Pointer<StartupInfoW>,
            Pointer<ProcessInformation>)>('CreateProcessW');
  }

  static Win32? _instance;

  static Win32 get instance => _instance ??= Win32._(
        DynamicLibrary.open('kernel32.dll'),
      );

  static bool get isWindows => Platform.isWindows;

  final DynamicLibrary _lib;

  late final int Function(int) getStdHandle;
  late final int Function(int, int) setConsoleMode;
  late final int Function(int, Pointer<Uint32>) getConsoleMode;
  late final int Function(int, Pointer<Uint8>, int, Pointer<Uint32>)
      readConsoleInput;
  late final int Function(int, Pointer<Uint32>) getNumberOfConsoleInputEvents;
  late final int Function(int, Pointer<Uint8>) getConsoleScreenBufferInfo;
  late final int Function(int) setConsoleOutputCP;
  late final int Function(int) setConsoleCP;
  late final int Function(int, int, int) openProcess;
  late final int Function(int, Pointer<Uint32>) getExitCodeProcess;
  late final int Function(int, int) terminateProcess;
  late final int Function(int) closeHandle;
  late final int Function(
          Pointer<Utf16>, int, int, Pointer<SecurityAttributes>, int, int, int)
      createFile;
  late final int Function(
      Pointer<Utf16>,
      Pointer<Utf16>,
      Pointer<SecurityAttributes>,
      Pointer<SecurityAttributes>,
      int,
      int,
      Pointer<Void>,
      Pointer<Utf16>,
      Pointer<StartupInfoW>,
      Pointer<ProcessInformation>) createProcess;

  /// Default/current text attribute word, used as a light/dark heuristic.
  int? consoleAttributes() {
    final handle = getStdHandle(stdOutputHandle);
    if (handle == 0) return null;
    final buffer = calloc<Uint8>(32);
    try {
      if (getConsoleScreenBufferInfo(handle, buffer) == 0) return null;
      return buffer
          .asTypedList(32)
          .buffer
          .asByteData()
          .getUint16(8, Endian.host);
    } finally {
      calloc.free(buffer);
    }
  }

  ({int columns, int rows})? consoleSize() {
    final handle = getStdHandle(stdOutputHandle);
    if (handle == 0) return null;
    final buffer = calloc<Uint8>(32);
    try {
      if (getConsoleScreenBufferInfo(handle, buffer) == 0) return null;
      final shorts = buffer.cast<Int16>();
      // SMALL_RECT srWindow: left, top, right, bottom at byte offset 10.
      final left = shorts[5];
      final top = shorts[6];
      final right = shorts[7];
      final bottom = shorts[8];
      final columns = right - left + 1;
      final rows = bottom - top + 1;
      if (columns <= 0 || rows <= 0) return null;
      return (columns: columns, rows: rows);
    } finally {
      calloc.free(buffer);
    }
  }

  /// Starts [exe] detached, with stdout/stderr appended to [logPath].
  /// Returns the child pid, or null when the call failed.
  int? startDetachedWithLog({
    required String exe,
    required List<String> arguments,
    required String logPath,
    String? workingDirectory,
  }) {
    final commandLine = _quoteCommandLine(exe, arguments);
    final logPathPtr = logPath.toNativeUtf16();
    final appPtr = exe.toNativeUtf16();
    final cmdPtr = commandLine.toNativeUtf16();
    final Pointer<Utf16>? workPtr = workingDirectory?.toNativeUtf16();
    final security = calloc<SecurityAttributes>();
    final startup = calloc<StartupInfoW>();
    final info = calloc<ProcessInformation>();
    var fileHandle = 0;
    var ok = false;
    try {
      security
        ..ref.nLength = sizeOf<SecurityAttributes>()
        ..ref.bInheritHandle = 1
        ..ref.lpSecurityDescriptor = nullptr;
      fileHandle = createFile(
        logPathPtr,
        fileAppendData,
        fileShareRead | fileShareWrite,
        security,
        openAlways,
        fileAttributeNormal,
        0,
      );
      if (fileHandle == 0 || fileHandle == -1) return null;
      startup.ref
        ..cb = sizeOf<StartupInfoW>()
        ..dwFlags = startfUseStdHandles
        ..hStdInput = 0
        ..hStdOutput = fileHandle
        ..hStdError = fileHandle;
      final result = createProcess(
        appPtr,
        cmdPtr,
        nullptr,
        nullptr,
        1,
        createNoWindow | createNewProcessGroup,
        nullptr,
        workPtr ?? nullptr,
        startup,
        info,
      );
      if (result == 0) return null;
      ok = true;
      return info.ref.dwProcessId;
    } finally {
      if (ok) {
        if (info.ref.hProcess != 0) closeHandle(info.ref.hProcess);
        if (info.ref.hThread != 0) closeHandle(info.ref.hThread);
      }
      if (fileHandle != 0 && fileHandle != -1) closeHandle(fileHandle);
      calloc
        ..free(security)
        ..free(startup)
        ..free(info)
        ..free(logPathPtr)
        ..free(appPtr)
        ..free(cmdPtr);
      if (workPtr != null) calloc.free(workPtr);
    }
  }

  bool isProcessAlive(int pid) {
    if (pid <= 0) return false;
    final handle = openProcess(processQueryLimitedInformation, 0, pid);
    if (handle == 0) return false;
    final code = calloc<Uint32>();
    try {
      if (getExitCodeProcess(handle, code) == 0) return false;
      return code.value == stillActive;
    } finally {
      calloc.free(code);
      closeHandle(handle);
    }
  }

  bool terminate(int pid) {
    final handle = openProcess(processTerminate, 0, pid);
    if (handle == 0) return false;
    try {
      return terminateProcess(handle, 1) != 0;
    } finally {
      closeHandle(handle);
    }
  }

  static String _quoteArgument(String value) {
    if (value.isEmpty) return '""';
    if (!value.contains(RegExp(r'[\s"]'))) return value;
    final buffer = StringBuffer('"');
    var backslashes = 0;
    for (final unit in value.codeUnits) {
      if (unit == 0x5c) {
        backslashes++;
      } else if (unit == 0x22) {
        buffer.write('\\' * (backslashes * 2 + 1));
        buffer.writeCharCode(unit);
        backslashes = 0;
      } else {
        buffer.write('\\' * backslashes);
        buffer.writeCharCode(unit);
        backslashes = 0;
      }
    }
    buffer.write('\\' * (backslashes * 2));
    buffer.write('"');
    return buffer.toString();
  }

  static String _quoteCommandLine(String exe, List<String> arguments) {
    final parts = <String>[
      _quoteArgument(exe),
      ...arguments.map(_quoteArgument),
    ];
    return parts.join(' ');
  }
}
