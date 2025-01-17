SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [CRC].[uspUpdateStep5SwapTables]
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	-------------------------------------------------------------
	-- Append "_OLD" to the current tables 
	-------------------------------------------------------------

	-- Data tables
	EXEC sp_rename 'CRC.PATIENT_DIMENSION', 'PATIENT_DIMENSION_OLD';
	EXEC sp_rename 'CRC.VISIT_DIMENSION', 'VISIT_DIMENSION_OLD';
	EXEC sp_rename 'CRC.OBSERVATION_FACT', 'OBSERVATION_FACT_OLD';
	EXEC sp_rename 'CRC.CONCEPT_DIMENSION', 'CONCEPT_DIMENSION_OLD';
	-- CQ2 tables
	EXEC sp_rename 'CRC.CQ2_FACT_COUNTS_CONCEPT_PATIENT', 'CQ2_FACT_COUNTS_CONCEPT_PATIENT_OLD';
	EXEC sp_rename 'CRC.CQ2_FACT_COUNTS_CONCEPT', 'CQ2_FACT_COUNTS_CONCEPT_OLD';
	EXEC sp_rename 'CRC.CQ2_CONCEPT_PATH', 'CQ2_CONCEPT_PATH_OLD';
	EXEC sp_rename 'CRC.CQ2_CONCEPT_PATH_CODE', 'CQ2_CONCEPT_PATH_CODE_OLD';
	EXEC sp_rename 'CRC.CQ2_FACT_COUNTS_PATH_PATIENT', 'CQ2_FACT_COUNTS_PATH_PATIENT_OLD';
	EXEC sp_rename 'CRC.CQ2_FACT_COUNTS_PATH', 'CQ2_FACT_COUNTS_PATH_OLD';
	EXEC sp_rename 'CRC.CQ2_SKETCH_PATH15x256', 'CQ2_SKETCH_PATH15x256_OLD';
	EXEC sp_rename 'CRC.CQ2_SKETCH_PATH8x256', 'CQ2_SKETCH_PATH8x256_OLD';
	EXEC sp_rename 'CRC.CQ2_SKETCH_PATIENT', 'CQ2_SKETCH_PATIENT_OLD';

	-------------------------------------------------------------
	-- Remove "_NEW" from the new tables
	-------------------------------------------------------------

	-- Data tables	
	EXEC sp_rename 'CRC.PATIENT_DIMENSION_NEW', 'PATIENT_DIMENSION';
	EXEC sp_rename 'CRC.VISIT_DIMENSION_NEW', 'VISIT_DIMENSION';
	EXEC sp_rename 'CRC.OBSERVATION_FACT_NEW', 'OBSERVATION_FACT';
	EXEC sp_rename 'CRC.CONCEPT_DIMENSION_NEW', 'CONCEPT_DIMENSION';
	-- CQ2 tables
	EXEC sp_rename 'CRC.CQ2_FACT_COUNTS_CONCEPT_PATIENT_NEW', 'CQ2_FACT_COUNTS_CONCEPT_PATIENT';
	EXEC sp_rename 'CRC.CQ2_FACT_COUNTS_CONCEPT_NEW', 'CQ2_FACT_COUNTS_CONCEPT';
	EXEC sp_rename 'CRC.CQ2_CONCEPT_PATH_NEW', 'CQ2_CONCEPT_PATH';
	EXEC sp_rename 'CRC.CQ2_CONCEPT_PATH_CODE_NEW', 'CQ2_CONCEPT_PATH_CODE';
	EXEC sp_rename 'CRC.CQ2_FACT_COUNTS_PATH_PATIENT_NEW', 'CQ2_FACT_COUNTS_PATH_PATIENT';
	EXEC sp_rename 'CRC.CQ2_FACT_COUNTS_PATH_NEW', 'CQ2_FACT_COUNTS_PATH';
	EXEC sp_rename 'CRC.CQ2_SKETCH_PATH15x256_NEW', 'CQ2_SKETCH_PATH15x256';
	EXEC sp_rename 'CRC.CQ2_SKETCH_PATH8x256_NEW', 'CQ2_SKETCH_PATH8x256';
	EXEC sp_rename 'CRC.CQ2_SKETCH_PATIENT_NEW', 'CQ2_SKETCH_PATIENT';

	-------------------------------------------------------------
	-- Swap the ontology tables (customize)
	-------------------------------------------------------------

	/*
	EXEC sp_rename 'ONT.I2B2', 'I2B2_OLD';
	EXEC sp_rename 'ONT.I2B2_NEW', 'I2B2';
	*/

END
GO
