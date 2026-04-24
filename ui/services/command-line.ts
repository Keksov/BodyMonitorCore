const quoteCommandLineArg = (value: string): string => {
  if (value === '') {
    return '""'
  }

  if (!/[\s"]/u.test(value)) {
    return value
  }

  let result = '"'
  let backslashCount = 0

  for (const char of value) {
    if (char === '\\') {
      backslashCount++
      continue
    }

    if (char === '"') {
      result += '\\'.repeat(backslashCount * 2 + 1) + char
      backslashCount = 0
      continue
    }

    result += '\\'.repeat(backslashCount) + char
    backslashCount = 0
  }

  result += '\\'.repeat(backslashCount * 2) + '"'
  return result
}

export const buildBodyMonitorCommandLine = (params: readonly string[]): string => {
  return ['BodyMonitor.exe', ...params].map(quoteCommandLineArg).join(' ')
}
