library jaguar_orm.generator.parser;

import 'package:tuple/tuple.dart';
import 'package:source_gen/source_gen.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/dart/constant/value.dart';

import 'package:jaguar_orm_gen/src/common/common.dart';
import 'package:jaguar_orm_gen/src/model/model.dart';
import 'package:jaguar_orm/jaguar_orm.dart' hide Field;

part 'next_gen.dart';

class FieldParseException implements Exception {
  dynamic inner;

  String fieldName;

  String message;

  StackTrace trace;

  FieldParseException(this.fieldName, this.inner, this.trace, {this.message});

  String toString() {
    var sb = StringBuffer();
    sb.writeln('Exception while parsing field: $fieldName!');
    if (message != null) {
      sb.writeln("Message: $message");
    }
    sb.writeln(inner);
    sb.writeln(trace);
    return sb.toString();
  }
}

/// Parses the `@GenBean()` into `WriterModel` so that `Model` can be used
/// to generate the code by `Writer`.
class ParsedBean {
  /// Should connect relations?
  ///
  /// Set this false to avoid connecting relations. Since connecting relations
  /// is recursive, this avoids infinite recursion. This shall be set only for
  /// the `Bean` being generated.
  final bool doRelations;
  final bool doAssociation;

  /// The [ClassElement] element of the `GenBean` spec.
  final ClassElement clazz;

  /// The model of the Bean
  DartType model;

  /// Constant reader used to read fields from the `GenBean`
  ConstantReader reader;

  /// Parsed fields are stored here while being parsed.
  ///
  /// This is part of the state of the parser.
  final fields = <String, Field>{};

  /// Parsed preloads are stored here while being parsed.
  ///
  /// This is part of the state of the parser.
  final preloads = <Preload>[];

  final primaries = <Field>[];

  final beanedAssociations = <DartType, BelongsToAssociation>{};

  final beanedForeignAssociations = <DartType, BeanedForeignAssociation>{};

  ParsedBean(this.clazz, {this.doRelations: true, this.doAssociation: true});

  WriterModel detect() {
    _getModel();

    _parseFields();

    // Collect [BelongsToAssociation] from [BelongsToForeign]
    _parseBelongsToAssociation();

    // Collect [BeanedForeignAssociation] from [BelongsToForeign]
    // TODO _parseBeanedForeignAssociation();

    // Collect [TabledForeignAssociation] from [TableForeign]
    for (Field f in fields.values) {
      if (f.foreign is! TableForeign) continue;

      throw UnimplementedError('ForeignKey that is not beaned!');

      /* TODO
      final ForeignTabled foreign = f.foreign;
      final String association = foreign.association;
      FindByForeign current = findByForeign[association];

      if (current == null) {
        current = FindByForeignTable(
            association, [], foreign.hasMany, foreign.table);
        findByForeign[association] = current;
      } else if (current is FindByForeignTable) {
        if (current.table != foreign.table) {
          throw Exception('Mismatching table for association!');
        }
        if (current.isMany != foreign.hasMany) {
          throw Exception('Mismatching ForeignKey association type!');
        }
      } else {
        throw Exception('Table and bean associations mixed!');
      }
      findByForeign[association].fields.add(f);
      */
    }

    for (BelongsToAssociation m in beanedAssociations.values) {
      final WriterModel info =
          ParsedBean(m.bean.element, doRelations: false, doAssociation: false)
              .detect();

      for (Field f in m.fields) {
        Field ff = info.fieldByColName(f.foreign.references);

        if (ff == null) {
          throw Exception(
              'Foreign key ${f.foreign.references} in foreign model not found!');
        }

        m.foreignFields.add(ff);
      }
    }

    for (BeanedForeignAssociation m in beanedForeignAssociations.values) {
      final WriterModel info =
          ParsedBean(m.bean.element, doRelations: false).detect();

      for (Field f in m.fields) {
        Field ff = info.fieldByColName(f.foreign.references);

        if (ff == null)
          throw Exception('Foreign key in foreign model not found!');

        m.foreignFields.add(ff);
      }
    }

    final ret = WriterModel(clazz.name, model.name, fields, primaries,
        beanedAssociations, beanedForeignAssociations, preloads);

    if (doRelations) {
      for (Preload p in preloads) {
        if (p.bean == clazz.type) {
          p.foreignFields.addAll(beanedAssociations[p.bean].fields);
        }
        for (Field f in p.foreignFields) {
          Field ff = ret.fieldByColName(f.foreign.references);
          if (ff == null)
            throw Exception('Foreign key in foreign model not found!');
          p.fields.add(ff);
        }
      }
    }

    return ret;
  }

  void _parseBelongsToAssociation() {
    // Collect [BelongsToAssociation] from [BelongsToForeign]
    for (Field f in fields.values) {
      if (!doAssociation) continue; // Skip associations?

      if (f.foreign is! BelongsToForeign) continue;

      final BelongsToForeign foreign = f.foreign;
      final DartType bean = foreign.bean;
      BelongsToAssociation current = beanedAssociations[bean];

      final WriterModel info =
          ParsedBean(bean.element, doRelations: false, doAssociation: false)
              .detect();

      final Preload other = info.findHasXByAssociation(clazz.type);

      if (other == null) continue;

      if (current == null) {
        bool byHasMany = foreign.byHasMany;
        if (byHasMany != null) {
          if (byHasMany != other.hasMany) {
            throw Exception('Mismatching association type!');
          }
        } else {
          byHasMany = other.hasMany;
        }
        current = BelongsToAssociation(bean, [], [], other, byHasMany);
        beanedAssociations[bean] = current;
      } else if (current is BelongsToAssociation) {
        if (current.byHasMany != other.hasMany) {
          throw Exception('Mismatching association type!');
        }
        if (current.belongsToMany != other is PreloadManyToMany) {
          throw Exception('Mismatching association type!');
        }
      } else {
        throw Exception('Table and bean associations mixed!');
      }
      beanedAssociations[bean].fields.add(f);
    }
  }

  void _parseBeanedForeignAssociation() {
    // Collect [BeanedForeignAssociation] from [BelongsToForeign]
    for (Field f in fields.values) {
      if (!doAssociation) continue;
      if (f.foreign is! BelongsToForeign) continue;

      final BelongsToForeign foreign = f.foreign;
      final DartType bean = foreign.bean;

      {
        final WriterModel info =
            ParsedBean(bean.element, doRelations: false, doAssociation: false)
                .detect();
        final Preload other = info.findHasXByAssociation(clazz.type);
        if (other != null) continue;
      }

      if (foreign.byHasMany == null)
        throw Exception(
            'For un-associated foreign keys, "byHasMany" must be specified!');

      BeanedForeignAssociation current = beanedForeignAssociations[bean];

      if (current == null) {
        current = BeanedForeignAssociation(bean, [], [], foreign.byHasMany);
        beanedForeignAssociations[bean] = current;
      } else if (current is BeanedForeignAssociation) {
        if (current.byHasMany != foreign.byHasMany) {
          throw Exception('Mismatching association type!');
        }
      } else {
        throw Exception('Table and bean associations mixed!');
      }
      beanedForeignAssociations[bean].fields.add(f);
    }
  }

  /// Parses and populates [model] and [reader]
  void _getModel() {
    if (!isBean.isAssignableFromType(clazz.type)) {
      throw Exception("Beans must implement Bean interface!");
    }

    final DartObject meta = isGenBean.firstAnnotationOf(clazz);
    if (meta == null) {
      throw Exception("GenBean annotation not found for ${clazz.name}!");
    }
    reader = ConstantReader(meta);

    final InterfaceType interface = clazz.allSupertypes
        .firstWhere((InterfaceType i) => isBean.isExactlyType(i));

    model = interface.typeArguments.first;

    if (model.isDynamic) throw Exception("Model cannot be dynamic!");
  }

  /// Parses and populates [fields]
  void _parseFields() {
    final ignores = Set<String>();

    final ClassElement modelClass = model.element;

    final relations = Set<String>();

    // Parse relations from GenBean::relations specification
    {
      final Map cols = reader.read('relations').mapValue;
      for (DartObject name in cols.keys) {
        final fieldName = name.toStringValue();
        final field = modelClass.getField(fieldName);

        if (field == null) throw Exception('Cannot find field $fieldName!');

        relations.add(fieldName);

        final DartObject spec = cols[name];
        parseRelation(clazz.type, field, spec);
      }
    }

    // Parse columns from GenBean::columns specification
    /*
    {
      final Map cols = reader.read('columns').mapValue;
      for (DartObject name in cols.keys) {
        final fieldName = name.toStringValue();

        if (relations.contains(fieldName))
          throw Exception(
              'Cannot have both a column and relation: $fieldName!');

        final field = modelClass.getField(fieldName);

        if (field == null) throw Exception('Cannot find field $fieldName!');

        final DartObject spec = cols[name];
        if (isIgnore.isExactlyType(spec.type)) {
          ignores.add(fieldName);
          continue;
        }

        final val = parseOldColumnSpec(field, spec);

        fields[val.field] = val;
        if (val.column.isPrimary != null) primaries.add(val);
      }
    }
     */

    /// Parse getters, setters and fields in model
    for (FieldElement field in modelClass.fields) {
      try {
        if (fields.containsKey(field.name)) continue;
        if (relations.contains(field.name)) continue;
        if (ignores.contains(field.name)) continue;

        if (field.displayName == 'hashCode' ||
            field.displayName == 'runtimeType') continue;

        // TODO allow setter only fields
        if (field.getter == null) continue;
        if (field.setter == null) {
          if (!field.isFinal || field.isSynthetic) continue;
        }

        if (isIgnore.hasAnnotationOf(field)) {
          ignores.add(field.name);
          continue;
        }

        if (field.isStatic) continue;

        if (!_relation(clazz.type, field)) {
          final val = _parseField(field);
          fields[val.field] = val;
          if (val.column.isPrimary) primaries.add(val);
        }
      } catch (e, s) {
        throw FieldParseException(field.name, e, s);
      }
    }
  }

  bool _relation(DartType curBean, FieldElement f) {
    DartObject rel = isRelation.firstAnnotationOf(f);
    if (rel == null) return false;
    parseRelation(curBean, f, rel);
    return true;
  }

  void parseRelation(DartType curBean, FieldElement f, DartObject obj) {
    if (isHasOne.isExactlyType(obj.type) || isHasMany.isExactlyType(obj.type)) {
      final DartType bean = obj.getField('bean').toTypeValue();

      if (!isBean.isAssignableFromType(bean)) {
        throw Exception("Non-bean type provided!");
      }

      BelongsToAssociation g;
      if (doRelations) {
        if (bean != curBean) {
          final WriterModel info =
              ParsedBean(bean.element, doRelations: false).detect();
          g = info.belongTos[curBean];
          if (g == null || g is! BelongsToAssociation)
            throw Exception('Association $bean not found! Field ${f.name}.');
        }
      }

      final bool hasMany = isHasMany.isExactlyType(obj.type);

      preloads.add(PreloadOneToX(bean, f.name, g?.fields ?? [], hasMany));
      return;
    } else if (isManyToMany.isExactlyType(obj.type)) {
      final DartType pivot = obj.getField('pivotBean').toTypeValue();
      final DartType target = obj.getField('targetBean').toTypeValue();

      if (!isBean.isAssignableFromType(pivot)) {
        throw Exception("Non-bean type provided!");
      }

      if (!isBean.isAssignableFromType(target)) {
        throw Exception("Non-bean type provided!");
      }

      BelongsToAssociation g;
      if (doRelations) {
        final WriterModel beanInfo =
            ParsedBean(pivot.element, doRelations: false).detect();
        g = beanInfo.belongTos[curBean];
        if (g == null || g is! BelongsToAssociation) {
          throw Exception('Association $curBean not found! Field ${f.name}.');
        }
        final WriterModel targetInfo =
            ParsedBean(target.element, doRelations: false).detect();
        preloads.add(PreloadManyToMany(
            pivot, target, f.name, targetInfo, beanInfo, g?.fields));
        return;
      }

      preloads.add(PreloadManyToMany(pivot, target, f.name, null, null, null));
      return;
    }

    throw Exception('Invalid Relation type!');
  }
}
