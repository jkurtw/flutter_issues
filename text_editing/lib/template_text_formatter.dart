import 'dart:math';

import 'package:flutter/services.dart';
import 'package:meta/meta.dart';

/// A formatter that provides automatic text formatting for a [TextField] or
/// [TextFormField] based on a template string.
///
/// Examples of template strings are:
/// - `??/??` for credit card expiry input, or
/// - `(???) ???-????` for US phone number input.
///
/// The template string uses '?' to represent a digit, all other characters
/// are used to format the string. '?' cannot be used as a string character.
///
/// A user cannot enter more digits than the template string supports.
class TemplateTextFormatter extends TextInputFormatter {
  TemplateTextFormatter({@required this.template})
      : assert(template != null),
        _maximumCollapsedLength =
            _templateDigitPattern.allMatches(template).length;

  final String template;

  /// The maximum length of the string once all formatting has been removed.
  final int _maximumCollapsedLength;

  /// The pattern used to find digits in the input string.
  static final _textDigitPattern = RegExp('\\d');

  /// The pattern used to find digits in the template string.
  static const _templateDigitPattern = '?';

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.length > oldValue.text.length) {
      return _formatText(newValue);
    }
    if (newValue.text.length < oldValue.text.length) {
      print('deletion');
      return _handleTextDeletion(oldValue, newValue);
    }
    // For cases where newValue.text.length >= oldValue.text.length,
    // _formatText handles all necessary formatting.
    return newValue;
  }

  /// Handles cases where the new text is shorter than the old text.
  ///
  /// When deleting, if the deleted character were not a digit, extra parts
  /// of the string need to be removed. An example of this is in the
  /// format: `(???) ???-????`, if the user has entered 1,2, then 3, the
  /// displayed text field will have `(123) `. Backspacing at this stage,
  /// should delete the 3, removing `) ` in the process.
  TextEditingValue _handleTextDeletion(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final oldDigitCount = _textDigitPattern.allMatches(oldValue.text).length;
    final newDigitCount = _textDigitPattern.allMatches(newValue.text).length;

    final isDigitDeleted = newDigitCount != oldDigitCount;
    if (!isDigitDeleted) {
      var baseOffset = newValue.selection.baseOffset;
      var extentOffset = newValue.selection.extentOffset;
      final digitIndex = newValue.text.lastIndexOf(
        _textDigitPattern,
        newValue.selection.baseOffset - 1,
      );
      if (digitIndex == -1) {
        // If there were no prior digits, just reformat the string.
        return _formatText(newValue);
      }

      final text = newValue.text.substring(0, digitIndex) +
          newValue.text.substring(newValue.selection.baseOffset);

      if (baseOffset > newValue.selection.baseOffset) {
        baseOffset -= newValue.selection.baseOffset - digitIndex;
      } else if (baseOffset >= digitIndex) {
        baseOffset = digitIndex;
      }
      if (extentOffset > newValue.selection.baseOffset) {
        extentOffset -= newValue.selection.baseOffset - digitIndex;
      } else if (extentOffset >= digitIndex) {
        extentOffset = digitIndex;
      }

      return _formatText(newValue.copyWith(
        text: text,
        selection: TextSelection(
          baseOffset: baseOffset,
          extentOffset: extentOffset,
        ),
      ));
    }

    // Instead of just returning newValue, call _formatText to ensure
    // mid-string or multi-character deletes result in correct formatting.
    return _formatText(newValue);
  }

  /// Formats a given string and selection offsets according to the template.
  TextEditingValue _formatText(TextEditingValue value) {
    // Collapse the string to only contain digits, updating the selection
    // offsets in the process.
    final collapsedValue = _collapse(value);

    // Ensure that the collapsed string does not exceed the maximum number
    // of input digits supported by the template
    final trimmedValue = _trim(collapsedValue);

    // Having no input is a special case where the prefix is not inserted
    // (i.e. _expand should not be called).
    //
    // Without this if statement, the input text field cannot be cleared
    // completely, which feels weird from a user perspective and also prevents
    // showing hint text.
    if (trimmedValue.text.isEmpty) {
      return trimmedValue;
    }

    // Format the string by inserting portions of the template string.
    return _expand(trimmedValue);
  }

  /// Returns a collapsed string with all non-digits removed and updated
  /// selection offsets.
  ///
  /// Example: If provided with `(123) 456-7890` with the cursor between `5`
  /// and `6` (offset 8), this will return `1234567890` with selection offset 5.
  TextEditingValue _collapse(TextEditingValue value) {
    final baseOffset = value.selection.baseOffset;
    final extentOffset = value.selection.extentOffset;

    final digitBuffer = StringBuffer();
    var lastOffset = 0;
    int collapsedBaseOffset;
    int collapsedExtentOffset;
    for (final match in _textDigitPattern.allMatches(value.text)) {
      if (lastOffset <= baseOffset && baseOffset <= match.start) {
        collapsedBaseOffset = digitBuffer.length;
      }
      if (lastOffset <= extentOffset && extentOffset <= match.start) {
        collapsedExtentOffset = digitBuffer.length;
      }
      digitBuffer.write(match[0]);
      lastOffset = match.end;
    }
    if (baseOffset >= lastOffset) collapsedBaseOffset = digitBuffer.length;
    if (extentOffset >= lastOffset) collapsedExtentOffset = digitBuffer.length;

    return value.copyWith(
      text: digitBuffer.toString(),
      selection: TextSelection(
        baseOffset: collapsedBaseOffset,
        extentOffset: collapsedExtentOffset,
      ),
    );
  }

  /// Trims the input string to the maximum length allowed by the template.
  ///
  /// Example: Returns `1234` when provided with `12345` and a template of
  /// `??/??`.
  TextEditingValue _trim(TextEditingValue value) {
    if (value.text.length <= _maximumCollapsedLength) return value;

    final text = value.text.substring(0, _maximumCollapsedLength);
    final baseOffset = min(value.selection.baseOffset, _maximumCollapsedLength);
    final extentOffset =
        min(value.selection.extentOffset, _maximumCollapsedLength);

    return value.copyWith(
      text: text,
      selection: TextSelection(
        baseOffset: baseOffset,
        extentOffset: extentOffset,
      ),
    );
  }

  /// Expands text according to the template string and updates selection
  /// offsets.
  ///
  /// Example: Returns `12/3` when provided with `123` and a template of `??/??`
  TextEditingValue _expand(TextEditingValue value) {
    final digits = value.text;
    final collapsedBaseOffset = value.selection.baseOffset;
    final collapsedExtentOffset = value.selection.extentOffset;

    StringBuffer textBuffer = StringBuffer();
    var lastOffset = 0;
    var numberOfDigitsWritten = 0;
    int expandedBaseOffset;
    int expandedExtentOffset;

    for (final match in _templateDigitPattern.allMatches(template)) {
      textBuffer.write(template.substring(lastOffset, match.start));

      if (collapsedBaseOffset == numberOfDigitsWritten) {
        expandedBaseOffset = textBuffer.length;
      }
      if (collapsedExtentOffset == numberOfDigitsWritten) {
        expandedExtentOffset = textBuffer.length;
      }
      if (numberOfDigitsWritten == digits.length) break;

      textBuffer.writeCharCode(digits.codeUnitAt(numberOfDigitsWritten));

      lastOffset = match.end;
      ++numberOfDigitsWritten;
    }
    textBuffer = StringBuffer((textBuffer.toString().trim()));
    expandedBaseOffset ??= textBuffer.length;
    expandedExtentOffset ??= textBuffer.length;

    return value.copyWith(
      text: textBuffer.toString(),
      selection: TextSelection.collapsed(
        offset: textBuffer.length,
      ),
    );
  }

  @override
  bool operator ==(dynamic other) {
    if (identical(this, other)) return true;
    if (other is! TemplateTextFormatter) return false;

    final typedOther = other as TemplateTextFormatter;
    return template == typedOther.template;
  }

  @override
  int get hashCode => template.hashCode;
}

class CreditCardTextInputFormatter extends TextInputFormatter {
  String formattedString = "";
  String rawString = "";
  CreditCardTextInputFormatter();

  String getRawString() {
    rawString = formattedString.replaceAll(" ", "").trim();
    return rawString;
  }

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    formattedString = newValue.text;
    var escapedString = getEscapedString(newValue.text);
    var position = newValue.selection.baseOffset -
        (newValue.text.length - escapedString.length);

    return newValue.copyWith(
        text: escapedString,
        selection: TextSelection.collapsed(offset: position));
  }

  getEscapedString(String text) {
    List<String> chunks = text.split("");
    List<String> padded = [];

    int group = 0;
    String cache = "";

    chunks.forEach((i) {
      group += 1;
      cache += i;

      if (group == 4) {
        padded.add(cache);
        group = 0;
        cache = "";
      }
    });

    if (cache.length > 0) {
      padded.add(cache);
      cache = "";
      group = 0;
    }
    return padded.join(" ");
  }
}
