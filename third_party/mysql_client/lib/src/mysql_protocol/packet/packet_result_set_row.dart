import 'dart:typed_data';
import 'package:mysql_client/mysql_protocol.dart';
import 'package:mysql_client/mysql_protocol_extension.dart';
import 'package:tuple/tuple.dart';

class MySQLResultSetRowPacket extends MySQLPacketPayload {
  List<String?> values;

  MySQLResultSetRowPacket({
    required this.values,
  });

  factory MySQLResultSetRowPacket.decode(
    Uint8List buffer,
    int numOfCols, [
    List<MySQLColumnDefinitionPacket>? colDefs,
  ]) {
    final byteData = ByteData.sublistView(buffer);
    int offset = 0;

    List<String?> values = [];

    for (int x = 0; x < numOfCols; x++) {
      Tuple2<String, int> value;
      final nextByte = byteData.getUint8(offset);

      if (nextByte == 0xfb) {
        values.add(null);
        offset += 1;
      } else {
        final binary = colDefs != null &&
            x < colDefs.length &&
            mysqlColumnHoldsRawBytes(
              columnType: colDefs[x].type.intVal,
              charset: colDefs[x].charset,
            );
        value = buffer.getLengthEncodedString(offset, latin1Bytes: binary);
        values.add(value.item1);
        offset += value.item2;
      }
    }

    return MySQLResultSetRowPacket(
      values: values,
    );
  }

  @override
  Uint8List encode() {
    throw UnimplementedError();
  }
}
