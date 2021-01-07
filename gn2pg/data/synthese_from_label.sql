/*
 SQL Scripts to automate populate of a GeoNature database from imported data

 Import steps when UPSERT data are:
   1. get or create Acquisition Framework (from Acquisition Framework UUID)
   2. get or create Dataset (from Dataset UUID)
   3. insert or update synthese data (from source/id_synthese, UUID may be NULL...)

 */

/* Acquisition Frameworks */



DROP FUNCTION IF EXISTS gn2pg_import.fct_c_get_or_insert_basic_af_from_uuid_name(_uuid UUID, _name TEXT);

CREATE OR REPLACE FUNCTION gn2pg_import.fct_c_get_or_insert_basic_af_from_uuid_name(_uuid UUID, _name TEXT) RETURNS INTEGER
AS
$$
DECLARE
    the_af_id INT ;
BEGIN
    insert into
        gn_meta.t_acquisition_frameworks ( unique_acquisition_framework_id, acquisition_framework_name
                                         , acquisition_framework_desc, acquisition_framework_start_date)
    select _uuid, _name, 'Description of acquisition framework : ' || _name, now()
    where
        not exists(
                select 1
                from
                    gn_meta.t_acquisition_frameworks
                where unique_acquisition_framework_id = _uuid
            );
    SELECT id_acquisition_framework
    into the_af_id
    FROM gn_meta.t_acquisition_frameworks
    WHERE unique_acquisition_framework_id = _uuid;

    RETURN the_af_id;
END
$$
    LANGUAGE plpgsql;


COMMENT ON FUNCTION gn2pg_import.fct_c_get_or_insert_basic_af_from_uuid_name(_uuid UUID, _name TEXT) IS 'function to basically create acquisition framework';

/* Datasets */
DROP FUNCTION IF EXISTS gn2pg_import.fct_c_get_or_insert_basic_dataset_from_uuid_name(_uuid UUID, _name TEXT, _id_af INT);

CREATE OR REPLACE FUNCTION gn2pg_import.fct_c_get_or_insert_basic_dataset_from_uuid_name(_uuid UUID, _name TEXT, _id_af INT) RETURNS INTEGER
AS
$$
DECLARE
    the_dataset_id INT ;
BEGIN
    INSERT INTO
        gn_meta.t_datasets( id_acquisition_framework
                          , dataset_name
                          , dataset_shortname
                          , dataset_desc
                          , marine_domain
                          , terrestrial_domain
                          , meta_create_date)
    SELECT
        _id_af
      , _name
      , left(_name, 30)
      , 'A compléter'
      , TRUE
      , TRUE
      , now()
    where
        not exists(
                select 1
                from
                    gn_meta.t_datasets
                where unique_dataset_id = _uuid
            );
    SELECT id_dataset
    into the_dataset_id
    FROM gn_meta.t_datasets
    WHERE unique_dataset_id = _uuid;

    RETURN the_dataset_id;
END
$$
    LANGUAGE plpgsql;


COMMENT ON FUNCTION gn2pg_import.fct_c_get_or_insert_basic_dataset_from_uuid_name(_uuid UUID, _name TEXT, _id_af INT) IS 'function to basically create acquisition framework';

/* Sources */


DROP FUNCTION IF EXISTS gn2pg_import.fct_c_get_or_insert_source(_source TEXT);

CREATE OR REPLACE FUNCTION gn2pg_import.fct_c_get_or_insert_source(_source TEXT) RETURNS INTEGER
AS
$$
DECLARE
    the_source_id INT ;
BEGIN
    INSERT INTO
        gn_synthese.t_sources(name_source)
    SELECT
        _source
    where
        not exists(
                select 1
                from
                    gn_synthese.t_sources
                where name_source = _source
            );
    SELECT id_source
    into the_source_id
    FROM gn_synthese.t_sources
    WHERE name_source = _source;

    RETURN the_source_id;
END
$$
    LANGUAGE plpgsql;


COMMENT ON FUNCTION gn2pg_import.fct_c_get_or_insert_source(_source TEXT) IS 'function to basically create new sources';


/*  Nomenclatures */

DROP FUNCTION IF EXISTS gn2pg_import.fct_c_get_id_nomenclature_from_label(_type TEXT, _label TEXT);
create or replace function gn2pg_import.fct_c_get_id_nomenclature_from_label(_type TEXT, _label TEXT) RETURNS INTEGER
AS
$$
DECLARE
    the_id_nomenclature INT;
BEGIN
    SELECT id_nomenclature
    INTO the_id_nomenclature
    FROM
        ref_nomenclatures.t_nomenclatures n
            join ref_nomenclatures.bib_nomenclatures_types t
                 on n.id_type = t.id_type
    WHERE t.mnemonique like _type and n.label_default = _label;
    RETURN the_id_nomenclature;
END
$$
    LANGUAGE plpgsql;

COMMENT ON FUNCTION gn2pg_import.fct_c_get_id_nomenclature_from_label(_type TEXT, _label TEXT) IS 'function to retrieve nomenclature ID from label';

/* UPSERT INTO Synthese */

create unique index IF NOT EXISTS uidx_synthese_id_source_id_entity_source_pk_value on gn_synthese.synthese(id_source, entity_source_pk_value);

DROP TRIGGER IF EXISTS tri_c_upsert_data_to_geonature ON gn2pg_import.data_json;

DROP FUNCTION IF EXISTS gn2pg_import.fct_tri_c_upsert_data_to_geonature() CASCADE;
CREATE OR REPLACE FUNCTION gn2pg_import.fct_tri_c_upsert_data_to_geonature() RETURNS TRIGGER
    LANGUAGE plpgsql
AS
$$
DECLARE
    _local_srid                              INT;
    the_unique_id_sinp                       UUID;
    the_unique_id_sinp_grp                   UUID;
    the_id_source                            INT;
--     id_module                                INT;
    the_entity_source_pk_value               INT;
    the_id_af                                INT;
    the_id_dataset                           INT;
    the_id_nomenclature_geo_object_nature    INT;
    the_id_nomenclature_grp_typ              INT;
    the_grp_method                           VARCHAR;
    the_id_nomenclature_obs_technique        INT;
    the_id_nomenclature_bio_status           INT;
    the_id_nomenclature_bio_condition        INT;
    the_id_nomenclature_naturalness          INT;
    the_id_nomenclature_exist_proof          INT;
    the_id_nomenclature_valid_status         INT;
    the_id_nomenclature_diffusion_level      INT;
    the_id_nomenclature_life_stage           INT;
    the_id_nomenclature_sex                  INT;
    the_id_nomenclature_obj_count            INT;
    the_id_nomenclature_type_count           INT;
    the_id_nomenclature_sensitivity          INT;
    the_id_nomenclature_observation_status   INT;
    the_id_nomenclature_blurring             INT;
    the_id_nomenclature_source_status        INT;
    the_id_nomenclature_info_geo_type        INT;
    the_id_nomenclature_behaviour            INT;
    the_id_nomenclature_biogeo_status        INT;
    the_reference_biblio                     VARCHAR;
    the_count_min                            INT;
    the_count_max                            INT;
    the_cd_nom                               INT;
    the_cd_hab                               INT;
    the_nom_cite                             VARCHAR;
    the_meta_v_taxref                        VARCHAR;
    the_sample_number_proof                  TEXT;
    the_digital_proof                        TEXT;
    the_non_digital_proof                    TEXT;
    the_altitude_min                         INT;
    the_altitude_max                         INT;
    the_depth_min                            INT;
    the_depth_max                            INT;
    the_place_name                           VARCHAR;
    _the_geom_4326                           GEOMETRY;
    _the_geom_point                          GEOMETRY;
    _the_geom_local                          GEOMETRY;
    the_precision                            INT;
    the_date_min                             TIMESTAMP;
    the_date_max                             TIMESTAMP;
    the_validator                            VARCHAR;
    the_validation_comment                   TEXT;
    the_observers                            TEXT;
    the_determiner                           TEXT;
    the_id_digitiser                         INT;
    the_id_nomenclature_determination_method INT;
    the_comment_context                      TEXT;
    the_comment_description                  TEXT;
    the_additional_data                      JSONB;
    the_meta_validation_date                 TIMESTAMP;
    the_meta_create_date                     TIMESTAMP;
    the_meta_update_date                     TIMESTAMP;
--     the_last_action                          VARCHAR;

BEGIN
    SELECT st_srid(the_geom_local) INTO _local_srid from gn_synthese.synthese limit 1;
    SELECT new.uuid INTO the_unique_id_sinp;
    SELECT CAST(new.item #>> '{id_perm_grp_sinp}' AS UUID) INTO the_unique_id_sinp_grp;
    SELECT gn2pg_import.fct_c_get_or_insert_source(new.source) INTO the_id_source;
--     id_module                                INT;
    select new.item #>> '{id_synthese}' INTO the_entity_source_pk_value;
    SELECT
        gn2pg_import.fct_c_get_or_insert_basic_af_from_uuid_name(
                CAST(new.item #>> '{ca_uuid}' AS UUID),
                new.item #>> '{ca_nom}')
    INTO the_id_af;
    SELECT
        gn2pg_import.fct_c_get_or_insert_basic_dataset_from_uuid_name(
                CAST(new.item #>> '{jdd_uuid}' AS UUID),
                new.item #>> '{jdd_nom}',
                the_id_af)
    INTO the_id_dataset;
    SELECT gn2pg_import.fct_c_get_id_nomenclature_from_label('NAT_OBJ_GEO', new.item #>> '{nature_objet_geo}')
    INTO the_id_nomenclature_geo_object_nature;
    SELECT gn2pg_import.fct_c_get_id_nomenclature_from_label('TYP_GRP', new.item #>> '{type_regroupement}')
    INTO the_id_nomenclature_grp_typ;
    SELECT new.item #>> '{methode_regroupement}' INTO the_grp_method;
    SELECT gn2pg_import.fct_c_get_id_nomenclature_from_label('METH_OBS', new.item #>> '{technique_obs}')
    INTO the_id_nomenclature_obs_technique;
    SELECT gn2pg_import.fct_c_get_id_nomenclature_from_label('STATUT_BIO', new.item #>> '{statut_biologique}')
    INTO the_id_nomenclature_bio_status;
    SELECT gn2pg_import.fct_c_get_id_nomenclature_from_label('ETA_BIO', new.item #>> '{etat_biologique}')
    INTO the_id_nomenclature_bio_condition;
    SELECT gn2pg_import.fct_c_get_id_nomenclature_from_label('NATURALITE', new.item #>> '{naturalite}')
    INTO the_id_nomenclature_naturalness;
    SELECT gn2pg_import.fct_c_get_id_nomenclature_from_label('PREUVE_EXIST', new.item #>> '{preuve_existante}')
    INTO the_id_nomenclature_exist_proof;
    SELECT gn2pg_import.fct_c_get_id_nomenclature_from_label('STATUT_VALID', new.item #>> '{statut_validation}')
    INTO the_id_nomenclature_valid_status;
    SELECT gn2pg_import.fct_c_get_id_nomenclature_from_label('NIV_PRECIS', new.item #>> '{precision_diffusion}')
    INTO the_id_nomenclature_diffusion_level;
    SELECT gn2pg_import.fct_c_get_id_nomenclature_from_label('STADE_VIE', new.item #>> '{stade_vie}')
    INTO the_id_nomenclature_life_stage;
    SELECT gn2pg_import.fct_c_get_id_nomenclature_from_label('SEXE', new.item #>> '{sexe}')
    INTO the_id_nomenclature_sex;
    SELECT gn2pg_import.fct_c_get_id_nomenclature_from_label('OBJ_DENBR', new.item #>> '{objet_denombrement}')
    INTO the_id_nomenclature_obj_count;
    SELECT gn2pg_import.fct_c_get_id_nomenclature_from_label('TYP_DENBR', new.item #>> '{type_denombrement}')
    INTO the_id_nomenclature_type_count;
    SELECT gn2pg_import.fct_c_get_id_nomenclature_from_label('SENSIBILITE', new.item #>> '{niveau_sensibilite}')
    INTO the_id_nomenclature_sensitivity;
    SELECT gn2pg_import.fct_c_get_id_nomenclature_from_label('STATUT_OBS', new.item #>> '{statut_observation}')
    INTO the_id_nomenclature_observation_status;
    SELECT gn2pg_import.fct_c_get_id_nomenclature_from_label('DEE_FLOU', new.item #>> '{floutage_dee}')
    INTO the_id_nomenclature_blurring;
    SELECT gn2pg_import.fct_c_get_id_nomenclature_from_label('STATUT_SOURCE', new.item #>> '{statut_source}')
    INTO the_id_nomenclature_source_status;
    SELECT gn2pg_import.fct_c_get_id_nomenclature_from_label('TYP_INF_GEO', new.item #>> '{type_info_geo}')
    INTO the_id_nomenclature_info_geo_type;
    SELECT gn2pg_import.fct_c_get_id_nomenclature_from_label('OCC_COMPORTEMENT', new.item #>> '{comportement}')
    INTO the_id_nomenclature_behaviour;
    SELECT gn2pg_import.fct_c_get_id_nomenclature_from_label('STAT_BIOGEO', new.item #>> '{statut_biogeo}')
    INTO the_id_nomenclature_biogeo_status;
    SELECT new.item #>> '{reference_biblio}' INTO the_reference_biblio;
    SELECT new.item #>> '{nombre_min}' INTO the_count_min;
    SELECT new.item #>> '{nombre_max}' INTO the_count_max;
    SELECT new.item #>> '{cd_nom}' INTO the_cd_nom;
    SELECT new.item #>> '{cd_hab}' INTO the_cd_hab;
    SELECT new.item #>> '{nom_cite}' INTO the_nom_cite;
    SELECT new.item #>> '{version_taxref}' INTO the_meta_v_taxref;
    SELECT new.item #>> '{numero_preuve}' INTO the_sample_number_proof;
    SELECT new.item #>> '{preuve_numerique}' INTO the_digital_proof;
    SELECT new.item #>> '{preuve_non_numerique}' INTO the_non_digital_proof;
    SELECT new.item #>> '{altitude_min}' INTO the_altitude_min;
    SELECT new.item #>> '{altitude_max}' INTO the_altitude_max;
    SELECT new.item #>> '{profondeur_min}' INTO the_depth_min;
    SELECT new.item #>> '{profondeur_max}' INTO the_depth_max;
    SELECT new.item #>> '{nom_lieu}' INTO the_place_name;
    SELECT st_setsrid(st_geomfromtext(new.item #>> '{wkt_4326}'), 4326) INTO _the_geom_4326;
    SELECT st_centroid(_the_geom_4326) INTO _the_geom_point;
    SELECT st_transform(_the_geom_4326, _local_srid) INTO _the_geom_local;
    SELECT cast(new.item #>> '{precision}' as INT) INTO the_precision;
    SELECT cast(new.item #>> '{date_debut}' as DATE) INTO the_date_min;
    SELECT cast(new.item #>> '{date_fin}' as DATE) INTO the_date_max;
    SELECT new.item #>> '{validateur}' INTO the_validator;
    SELECT new.item #>> '{comment_validation}' INTO the_validation_comment;
    SELECT new.item #>> '{observateurs}' INTO the_observers;
    SELECT new.item #>> '{determinateur}' INTO the_determiner;
    SELECT NULL INTO the_id_digitiser;
    SELECT gn2pg_import.fct_c_get_id_nomenclature_from_label('TYPE', new.item #>> '{label}')
    INTO the_id_nomenclature_determination_method;
    SELECT new.item #>> '{comment_releve}' INTO the_comment_context;
    SELECT new.item #>> '{comment_occurence}' INTO the_comment_description;
    SELECT null INTO the_additional_data;
    SELECT null INTO the_meta_validation_date;
    SELECT new.item #>> '{date_creation}' INTO the_meta_create_date;
    SELECT new.item #>> '{date_modification}' INTO the_meta_update_date;
--     SELECT new.item #>> '{derniere_action}' INTO the_last_action;

    INSERT INTO
        gn_synthese.synthese( unique_id_sinp
                            , unique_id_sinp_grp
                            , id_source
                            , entity_source_pk_value
                            , id_dataset
                            , id_nomenclature_geo_object_nature
                            , id_nomenclature_grp_typ
                            , grp_method
                            , id_nomenclature_obs_technique
                            , id_nomenclature_bio_status
                            , id_nomenclature_bio_condition
                            , id_nomenclature_naturalness
                            , id_nomenclature_exist_proof
                            , id_nomenclature_valid_status
                            , id_nomenclature_diffusion_level
                            , id_nomenclature_life_stage
                            , id_nomenclature_sex
                            , id_nomenclature_obj_count
                            , id_nomenclature_type_count
                            , id_nomenclature_sensitivity
                            , id_nomenclature_observation_status
                            , id_nomenclature_blurring
                            , id_nomenclature_source_status
                            , id_nomenclature_info_geo_type
                            , id_nomenclature_behaviour
                            , id_nomenclature_biogeo_status
                            , reference_biblio
                            , count_min
                            , count_max
                            , cd_nom
                            , cd_hab
                            , nom_cite
                            , meta_v_taxref
                            , sample_number_proof
                            , digital_proof
                            , non_digital_proof
                            , altitude_min
                            , altitude_max
                            , depth_min
                            , depth_max
                            , place_name
                            , the_geom_4326
                            , the_geom_point
                            , the_geom_local
                            , precision
                            , date_min
                            , date_max
                            , validator
                            , validation_comment
                            , observers
                            , determiner
                            , id_digitiser
                            , id_nomenclature_determination_method
                            , comment_context
                            , comment_description
                            , additional_data
                            , meta_validation_date
                            , meta_create_date
                            , meta_update_date
                            , last_action)
    VALUES
    ( the_unique_id_sinp
    , the_unique_id_sinp_grp
    , the_id_source
    , the_entity_source_pk_value
    , the_id_dataset
    , the_id_nomenclature_geo_object_nature
    , the_id_nomenclature_grp_typ
    , the_grp_method
    , the_id_nomenclature_obs_technique
    , the_id_nomenclature_bio_status
    , the_id_nomenclature_bio_condition
    , the_id_nomenclature_naturalness
    , the_id_nomenclature_exist_proof
    , the_id_nomenclature_valid_status
    , the_id_nomenclature_diffusion_level
    , the_id_nomenclature_life_stage
    , the_id_nomenclature_sex
    , the_id_nomenclature_obj_count
    , the_id_nomenclature_type_count
    , the_id_nomenclature_sensitivity
    , the_id_nomenclature_observation_status
    , the_id_nomenclature_blurring
    , the_id_nomenclature_source_status
    , the_id_nomenclature_info_geo_type
    , the_id_nomenclature_behaviour
    , the_id_nomenclature_biogeo_status
    , the_reference_biblio
    , the_count_min
    , the_count_max
    , the_cd_nom
    , the_cd_hab
    , the_nom_cite
    , the_meta_v_taxref
    , the_sample_number_proof
    , the_digital_proof
    , the_non_digital_proof
    , the_altitude_min
    , the_altitude_max
    , the_depth_min
    , the_depth_max
    , the_place_name
    , _the_geom_4326
    , _the_geom_point
    , _the_geom_local
    , the_precision
    , the_date_min
    , the_date_max
    , the_validator
    , the_validation_comment
    , the_observers
    , the_determiner
    , the_id_digitiser
    , the_id_nomenclature_determination_method
    , the_comment_context
    , the_comment_description
    , the_additional_data
    , the_meta_validation_date
    , the_meta_create_date
    , the_meta_update_date
    , 'I')
    ON CONFLICT (id_source, entity_source_pk_value)
        DO UPDATE
        SET
            unique_id_sinp                       = the_unique_id_sinp
          , unique_id_sinp_grp                   = the_unique_id_sinp_grp
          , id_source                            = the_id_source
          , entity_source_pk_value               = the_entity_source_pk_value
          , id_dataset                           = the_id_dataset
          , id_nomenclature_geo_object_nature    = the_id_nomenclature_geo_object_nature
          , id_nomenclature_grp_typ              = the_id_nomenclature_grp_typ
          , grp_method                           = the_grp_method
          , id_nomenclature_obs_technique        = the_id_nomenclature_obs_technique
          , id_nomenclature_bio_status           = the_id_nomenclature_bio_status
          , id_nomenclature_bio_condition        = the_id_nomenclature_bio_condition
          , id_nomenclature_naturalness          = the_id_nomenclature_naturalness
          , id_nomenclature_exist_proof          = the_id_nomenclature_exist_proof
          , id_nomenclature_valid_status         = the_id_nomenclature_valid_status
          , id_nomenclature_diffusion_level      = the_id_nomenclature_diffusion_level
          , id_nomenclature_life_stage           = the_id_nomenclature_life_stage
          , id_nomenclature_sex                  = the_id_nomenclature_sex
          , id_nomenclature_obj_count            = the_id_nomenclature_obj_count
          , id_nomenclature_type_count           = the_id_nomenclature_type_count
          , id_nomenclature_sensitivity          = the_id_nomenclature_sensitivity
          , id_nomenclature_observation_status   = the_id_nomenclature_observation_status
          , id_nomenclature_blurring             = the_id_nomenclature_blurring
          , id_nomenclature_source_status        = the_id_nomenclature_source_status
          , id_nomenclature_info_geo_type        = the_id_nomenclature_info_geo_type
          , id_nomenclature_behaviour            = the_id_nomenclature_behaviour
          , id_nomenclature_biogeo_status        = the_id_nomenclature_biogeo_status
          , reference_biblio                     = the_reference_biblio
          , count_min                            = the_count_min
          , count_max                            = the_count_max
          , cd_nom                               = the_cd_nom
          , cd_hab                               = the_cd_hab
          , nom_cite                             = the_nom_cite
          , meta_v_taxref                        = the_meta_v_taxref
          , sample_number_proof                  = the_sample_number_proof
          , digital_proof                        = the_digital_proof
          , non_digital_proof                    = the_non_digital_proof
          , altitude_min                         = the_altitude_min
          , altitude_max                         = the_altitude_max
          , depth_min                            = the_depth_min
          , depth_max                            = the_depth_max
          , place_name                           = the_place_name
          , the_geom_4326                        = _the_geom_4326
          , the_geom_point                       = _the_geom_point
          , the_geom_local                       = _the_geom_local
          , precision                            = the_precision
          , date_min                             = the_date_min
          , date_max                             = the_date_max
          , validator                            = the_validator
          , validation_comment                   = the_validation_comment
          , observers                            = the_observers
          , determiner                           = the_determiner
          , id_digitiser                         = the_id_digitiser
          , id_nomenclature_determination_method = the_id_nomenclature_determination_method
          , comment_context                      = the_comment_context
          , comment_description                  = the_comment_description
          , additional_data                      = the_additional_data
          , meta_validation_date                 = the_meta_validation_date
          , meta_create_date                     = the_meta_create_date
          , meta_update_date                     = the_meta_update_date
          , last_action                          = 'U';
    RETURN new;
END;
$$;


COMMENT ON FUNCTION gn2pg_import.fct_tri_c_upsert_data_to_geonature() IS 'Trigger function to upsert datas from import to synthese';

DROP TRIGGER IF EXISTS tri_c_upsert_data_to_geonature ON gn2pg_import.data_json;

CREATE TRIGGER tri_c_upsert_data_to_geonature
    AFTER INSERT OR UPDATE
    ON gn2pg_import.data_json
    FOR EACH ROW
EXECUTE PROCEDURE gn2pg_import.fct_tri_c_upsert_data_to_geonature();
