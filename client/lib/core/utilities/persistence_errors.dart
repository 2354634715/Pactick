import 'package:sqflite/sqflite.dart';

String persistenceErrorMessage(Object error) {
  if (error is DatabaseException) {
    if (error.isReadOnlyError()) {
      return '保存失败：本机存储当前不可写。输入已保留，请恢复存储权限后重试。';
    }
    if (error.toString().toLowerCase().contains('disk is full')) {
      return '保存失败：本机存储空间不足。输入已保留，请释放空间后重试。';
    }
    if (error.isDatabaseClosedError() || error.isOpenFailedError()) {
      return '保存失败：本机存储暂时无法打开。输入已保留，请稍后重试。';
    }
  }
  return '保存失败：本机写入未完成。输入已保留，请稍后重试。';
}
