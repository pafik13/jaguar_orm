part of query.core;

class AliasedRowSource {
  final RowSource source;

  final String alias;

  AliasedRowSource(this.source, {this.alias});
}

/// Table selector
abstract class RowSource {}

/// TableName
class Table implements RowSource {
  final String name;

  Table(this.name);
}

class Row {
  final List<dynamic> columns;

  Row(this.columns);
}

class Values implements RowSource {
  final List<Row> rows;

  Values(this.rows);
}

/// A SQL join type that can be used in 'SELECT' statements
class JoinType {
  /// Identification code for this join type
  final int id;

  /// String representation of this join type
  final String string;

  const JoinType._(this.id, this.string);

  /// 'INNER JOIN' join type
  static const JoinType InnerJoin = const JoinType._(0, 'INNER JOIN');

  /// 'LEFT JOIN' join type
  static const JoinType LeftJoin = const JoinType._(1, 'LEFT JOIN');

  /// 'RIGHT JOIN' join type
  static const JoinType RightJoin = const JoinType._(2, 'RIGHT JOIN');

  /// 'FULL JOIN' join type
  static const JoinType FullJoin = const JoinType._(3, 'FULL JOIN');

  /// 'CROSS JOIN' join type
  static const JoinType CrossJoin = const JoinType._(4, 'CROSS JOIN');
}

class JoinedTable {
  final JoinType _type;

  AliasedRowSource _to;

  final _on = And();

  JoinedTable(this._type, /* String | RowSource */ source, [String alias]) {
    _info = QueryJoinedTableInfo(this);

    if (source is String) {
      source = Table(source);
    }
    if (source is RowSource) {
      _to = AliasedRowSource(source, alias: alias);
    } else {
      throw UnsupportedError("");
    }
  }

  factory JoinedTable.innerJoin(String tableName, [String alias]) =>
      JoinedTable(JoinType.InnerJoin, tableName, alias);

  factory JoinedTable.leftJoin(String tableName, [String alias]) =>
      JoinedTable(JoinType.LeftJoin, tableName, alias);

  factory JoinedTable.rightJoin(String tableName, [String alias]) =>
      JoinedTable(JoinType.RightJoin, tableName, alias);

  factory JoinedTable.fullJoin(String tableName, [String alias]) =>
      JoinedTable(JoinType.FullJoin, tableName, alias);

  factory JoinedTable.crossJoin(String tableName, [String alias]) =>
      JoinedTable(JoinType.CrossJoin, tableName, alias);

  JoinedTable joinOn(Expression onExp) {
    if (_type == null || _to == null) {
      throw Exception('Query has no join on it!');
    }

    _on.and(onExp);

    return this;
  }

  void validate() {
    if (_to == null) {
      if (_type != null || _on.length != 0) {
        throw Exception('Join not initialized properly!');
      }
    } else {
      if (_type == null || _on.length == 0) {
        throw Exception('Join not initialized properly!');
      }
    }
  }

  QueryJoinedTableInfo _info;

  QueryJoinedTableInfo get info => _info;
}

class QueryJoinedTableInfo {
  final JoinedTable _inner;

  QueryJoinedTableInfo(this._inner);

  JoinType get type => _inner._type;

  AliasedRowSource get to => _inner._to;

  // TODO immutable
  And get on => _inner._on;
}
