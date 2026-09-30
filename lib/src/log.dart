import 'dart:io';

/// Writes a diagnostic line to stderr.
///
/// stdout carries the MCP protocol, so diagnostics must never go there.
void log(String message) => stderr.writeln('[smartschool_mcp] $message');
