SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[uspGetSqlTableSchema]
	@TABLE_SCHEMA VARCHAR(1000) = 'DBO',
	@TABLE_NAME VARCHAR(1000)
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;


	;WITH tables_a AS (
		SELECT TABLE_SCHEMA, TABLE_NAME, SchemaTable, ordinal_position,
			'['+[column_name]+'] '
			+UPPER(data_type)
			+(CASE WHEN data_type IN ('varchar','nvarchar','char','binary','varbinary') 
				THEN (CASE WHEN character_maximum_length < 0 THEN '(max)' ELSE '('+CAST(character_maximum_length AS VARCHAR(50))+')' END)
				WHEN data_type IN ('decimal')
				THEN '('+CAST(numeric_precision AS VARCHAR(50))+','+CAST(numeric_scale AS VARCHAR(50))+')'
				ELSE '' END)
			+(CASE WHEN COLUMNPROPERTY(OBJECT_ID(SchemaTable),column_name,'IsIdentity')=1
				THEN ' IDENTITY('+CAST(IDENT_SEED(SchemaTable) AS VARCHAR(50))+','+CAST(IDENT_INCR(SchemaTable) AS VARCHAR(50))+')'
				ELSE '' END)
			+(CASE WHEN is_nullable = 'NO' THEN ' NOT NULL' ELSE '' END)
			ColumnSQL
		FROM (
			SELECT *, '['+TABLE_SCHEMA+'].['+TABLE_NAME+']' SchemaTable
			FROM INFORMATION_SCHEMA.COLUMNS
			WHERE TABLE_SCHEMA = @TABLE_SCHEMA AND TABLE_NAME = @TABLE_NAME
		) t
	), tables_b AS (
		SELECT DISTINCT TABLE_SCHEMA, TABLE_NAME, SchemaTable FROM tables_a
	), tablesSQL AS (
		SELECT 'tables' objectType, TABLE_SCHEMA, TABLE_NAME, SchemaTable, NULL ItemName,
			'CREATE TABLE '+SchemaTable+' ('+CHAR(10)
			+CAST((
				SELECT (CASE WHEN ordinal_position = 1 THEN '' ELSE ','+CHAR(10) END) + CHAR(9) 
					+ ColumnSQL
				FROM tables_a a
				WHERE a.SchemaTable = b.SchemaTable
				ORDER BY ordinal_position
				FOR XML PATH(''), TYPE
			) AS NVARCHAR(MAX)) 
			+CHAR(10)+')'+CHAR(10)+CHAR(10) TableSQL
		FROM tables_b b
	), indexes_a AS (
		SELECT SCHEMA_NAME(t.schema_id) SchemaName, t.name TableName, 
			'['+SCHEMA_NAME(t.schema_id)+'].['+t.name+']' SchemaTable,
			i.name IndexName, i.is_primary_key, i.is_unique, i.is_unique_constraint, 
			(CASE i.type WHEN 1 THEN 'CLUSTERED' WHEN 2 THEN 'NONCLUSTERED' ELSE '' END) ClusterType,
			x.key_ordinal, x.is_descending_key, x.is_included_column, 
			'['+c.name+']' ColumnName,
			ROW_NUMBER() OVER (PARTITION BY t.schema_id, t.name, i.name, x.is_included_column 
				ORDER BY x.key_ordinal, c.name) ColumnSort
		FROM sys.tables t
			INNER JOIN sys.indexes i 
				ON t.object_id = i.object_id
			INNER JOIN sys.index_columns x 
				ON i.object_id = x.object_id AND i.index_id = x.index_id
			INNER JOIN sys.columns c
				ON c.object_id = t.object_id AND x.column_id = c.column_id
		WHERE SCHEMA_NAME(t.schema_id) = @TABLE_SCHEMA AND t.name = @TABLE_NAME
	), indexes_b AS (
		SELECT SchemaName, TableName, SchemaTable, IndexName, 
			is_primary_key, is_unique, is_unique_constraint, 
			ClusterType, max(is_included_column*1) has_include
		FROM indexes_a a
		GROUP BY SchemaName, TableName, SchemaTable, IndexName, 
			is_primary_key, is_unique, is_unique_constraint, 
			ClusterType
	), indexesSQL AS (
		SELECT 'indexes' objectType, SchemaName, TableName, SchemaTable, IndexName ItemName,
			(CASE WHEN is_primary_key = 1 
				THEN 'ALTER TABLE '+SchemaTable+' ADD PRIMARY KEY '+(CASE WHEN ClusterType='CLUSTERED' THEN '' ELSE ClusterType+' ' END)+'('
				ELSE 'CREATE '+(CASE WHEN is_unique = 1 THEN 'UNIQUE ' ELSE '' END)+ClusterType+' INDEX '+IndexName+' ON '+SchemaTable+'('
				END)
			+CAST((
				SELECT (CASE WHEN key_ordinal = 1 THEN '' ELSE ',' END)
					+ ColumnName + (CASE WHEN is_descending_key = 1 THEN ' DESC' ELSE '' END)
				FROM indexes_a a
				WHERE a.SchemaTable = b.SchemaTable and a.IndexName = b.IndexName
					AND is_included_column = 0
				ORDER BY key_ordinal
				FOR XML PATH(''), TYPE
			) AS NVARCHAR(MAX)) 
			+(CASE WHEN has_include = 1 
				THEN ') INCLUDE ('
					+CAST((
						SELECT (CASE WHEN ColumnSort = 1 THEN '' ELSE ',' END)
							+ ColumnName + (CASE WHEN is_descending_key = 1 THEN ' DESC' ELSE '' END)
						FROM indexes_a a
						WHERE a.SchemaTable = b.SchemaTable and a.IndexName = b.IndexName
							AND is_included_column = 1
						ORDER BY ColumnSort
						FOR XML PATH(''), TYPE
					) AS NVARCHAR(MAX)) 
				ELSE '' END)
			+')'+' WITH (SORT_IN_TEMPDB=ON)'+CHAR(10) IndexSQL
		FROM indexes_b b
	), defaultSQL AS (
		SELECT 'default constraints' ObjectType, s.name SchemaName, t.name ObjectName, 
			'['+s.name+'].['+t.name+']' SchemaObject,
			d.name ItemName,
			'ALTER TABLE ['+s.name+'].['+t.name+'] ADD DEFAULT '
				+SUBSTRING(d.definition,2,LEN(d.definition)-2)
				+' FOR '+c.name+CHAR(10) ObjectSQL
		FROM sys.default_constraints d
			INNER JOIN sys.columns c
				ON d.parent_object_id = c.object_id AND d.parent_column_id = c.column_id
			INNER JOIN sys.tables t 
				ON t.object_id = c.object_id
			INNER JOIN sys.schemas s
				ON s.schema_id = t.schema_id
		WHERE SCHEMA_NAME(t.schema_id) = @TABLE_SCHEMA AND t.name = @TABLE_NAME
	), FKConstraints AS (
		SELECT *, 
			'['+SchemaName+'].['+ObjectName+']' SchemaObject,
			'['+rSchemaName+'].['+rObjectName+']' rSchemaObject
		FROM (
			SELECT	SCHEMA_NAME(p.schema_id) SchemaName, p.name ObjectName, 
					SCHEMA_NAME(r.schema_id) rSchemaName, r.name rObjectName, 
					k.object_id, k.name ItemName
			FROM sys.foreign_keys k
				INNER JOIN sys.tables p
					ON k.parent_object_id = p.object_id
				INNER JOIN sys.tables r
					ON k.referenced_object_id = r.object_id
			WHERE SCHEMA_NAME(p.schema_id) = @TABLE_SCHEMA AND p.name = @TABLE_NAME
		) t
	), FKColumns AS (
		SELECT c.constraint_object_id, c.constraint_column_id, q.name pName, s.name rName
		FROM sys.foreign_key_columns c
			INNER JOIN sys.columns q
				ON c.parent_object_id = q.object_id AND c.parent_column_id = q.column_id
			INNER JOIN sys.columns s
				ON c.referenced_object_id = s.object_id AND c.referenced_column_id = s.column_id
	), fkSQL AS (
		SELECT 'foreign keys' ObjectType, SchemaName, ObjectName, SchemaObject, ItemName,
			'ALTER TABLE '+SchemaObject+' ADD CONSTRAINT '+ItemName+' FOREIGN KEY ('
			+CAST((
				SELECT (CASE WHEN constraint_column_id = 1 THEN '' ELSE ',' END)
					+ pName
				FROM FKColumns c
				WHERE c.constraint_object_id = t.object_id
				ORDER BY constraint_column_id
				FOR XML PATH(''), TYPE
			) AS NVARCHAR(MAX)) 
			+') REFERENCES '+rSchemaObject+'('
			+CAST((
				SELECT (CASE WHEN constraint_column_id = 1 THEN '' ELSE ',' END)
					+ rName
				FROM FKColumns c
				WHERE c.constraint_object_id = t.object_id
				ORDER BY constraint_column_id
				FOR XML PATH(''), TYPE
			) AS NVARCHAR(MAX)) 
			+')'+CHAR(10) ObjectSQL
		FROM FKConstraints t
	), AllObjects AS(
		SELECT TypeSort, ObjectType, SchemaName, ObjectName, SchemaObject, ItemName, ObjectSQL,
			ROW_NUMBER() OVER (ORDER BY TypeSort, SchemaObject, ObjectSQL) AllObjectSort,
			ROW_NUMBER() OVER (PARTITION BY TypeSort, SchemaObject ORDER BY ObjectSQL) ObjectItemSort,
			ROW_NUMBER() OVER (PARTITION BY TypeSort ORDER BY SchemaObject, ObjectSQL) ObjectTypeSort
		FROM (
			SELECT	(CASE ObjectType
						WHEN 'tables' THEN 1
						WHEN 'indexes' THEN 2
						WHEN 'default constraints' THEN 3
						WHEN 'foreign keys' THEN 4
						ELSE 9 END) TypeSort,
					*
			FROM (
				SELECT '' ObjectType, '' SchemaName, '' ObjectName, '' SchemaObject, '' ItemName, '' ObjectSQL WHERE 1=0
				UNION ALL SELECT * FROM tablesSQL
				UNION ALL SELECT * FROM indexesSQL
				UNION ALL SELECT * FROM defaultSQL
				UNION ALL SELECT * FROM fkSQL
			) t
		) t
	)
	SELECT (
		SELECT ObjectSQL+''
		FROM AllObjects
		ORDER BY AllObjectSort
		FOR XML PATH(''), TYPE) SQL


END
GO
