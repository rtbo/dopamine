module pgd.libpq.defs;

// pg_config_ext.h
alias PG_INT64_TYPE = long;

// postgres_ext.h
alias Oid = uint;
enum Oid InvalidOid = 0;
alias pg_int64 = PG_INT64_TYPE;

enum PG_DIAG_SEVERITY = 'S';
enum PG_DIAG_SEVERITY_NONLOCALIZED = 'V';
enum PG_DIAG_SQLSTATE = 'C';
enum PG_DIAG_MESSAGE_PRIMARY = 'M';
enum PG_DIAG_MESSAGE_DETAIL = 'D';
enum PG_DIAG_MESSAGE_HINT = 'H';
enum PG_DIAG_STATEMENT_POSITION = 'P';
enum PG_DIAG_INTERNAL_POSITION = 'p';
enum PG_DIAG_INTERNAL_QUERY = 'q';
enum PG_DIAG_CONTEXT = 'W';
enum PG_DIAG_SCHEMA_NAME = 's';
enum PG_DIAG_TABLE_NAME = 't';
enum PG_DIAG_COLUMN_NAME = 'c';
enum PG_DIAG_DATATYPE_NAME = 'd';
enum PG_DIAG_CONSTRAINT_NAME = 'n';
enum PG_DIAG_SOURCE_FILE = 'F';
enum PG_DIAG_SOURCE_LINE = 'L';
enum PG_DIAG_SOURCE_FUNCTION = 'R';

// libpq-fe.h

enum LIBPQ_HAS_PIPELINING = 1;
enum LIBPQ_HAS_TRACE_FLAGS = 1;

enum PG_COPYRES_ATTRS = 0x01;
enum PG_COPYRES_TUPLES = 0x02;
enum PG_COPYRES_EVENTS = 0x04;
enum PG_COPYRES_NOTICEHOOKS = 0x08;

enum ConnStatus
{
    OK,
    BAD,
    /* Non-blocking mode only below here */

    /*
	 * The existence of these should never be relied upon - they should only
	 * be used for user feedback or similar purposes.
	 */
    STARTED, /* Waiting for connection to be made.  */
    MADE, /* Connection OK; waiting to send.     */
    AWAITING_RESPONSE, /* Waiting for a response from the
									 * postmaster.        */
    AUTH_OK, /* Received authentication; waiting for
								 * backend startup. */
    SETENV, /* This state is no longer used. */
    SSL_STARTUP, /* Negotiating SSL. */
    NEEDED, /* Internal state: connect() needed */
    CHECK_WRITABLE, /* Checking if session is read-write. */
    CONSUME, /* Consuming any extra messages. */
    GSS_STARTUP, /* Negotiating GSSAPI. */
    CHECK_TARGET, /* Checking target server properties. */
    CHECK_STANDBY /* Checking if server is in standby mode. */
}

enum PostgresPollingStatus
{
    FAILED = 0,
    READING, /* These two indicate that one may	  */
    WRITING, /* use select before polling again.   */
    OK,
}

enum ExecStatus
{
    EMPTY_QUERY = 0, /* empty query string was executed */
    COMMAND_OK, /* a query command that doesn't return
								 * anything was executed properly by the
								 * backend */
    TUPLES_OK, /* a query command that returns tuples was
								 * executed properly by the backend, PGresult
								 * contains the result tuples */
    COPY_OUT, /* Copy Out data transfer in progress */
    COPY_IN, /* Copy In data transfer in progress */
    BAD_RESPONSE, /* an unexpected response was recv'd from the
								 * backend */
    NONFATAL_ERROR, /* notice or warning message */
    FATAL_ERROR, /* query failed */
    COPY_BOTH, /* Copy In/Out data transfer in progress */
    SINGLE_TUPLE, /* single tuple from larger resultset */
    PIPELINE_SYNC, /* pipeline synchronization point */
    PIPELINE_ABORTED /* Command didn't run because of an abort
								 * earlier in a pipeline */
}

enum PGTransactionStatus
{
    IDLE, /* connection idle */
    ACTIVE, /* command in progress */
    INTRANS, /* idle, within transaction block */
    INERROR, /* idle, within failed transaction */
    UNKNOWN /* cannot determine status */
}

enum PGVerbosity
{
    TERSE, /* single-line error messages */
    DEFAULT, /* recommended style */
    VERBOSE, /* all the facts, ma'am */
    SQLSTATE /* only error severity and SQLSTATE code */
}

enum PGContextVisibility
{
    NEVER, /* never show CONTEXT field */
    ERRORS, /* show CONTEXT for errors only (default) */
    ALWAYS /* always show CONTEXT field */
}

/*
 * PGPing - The ordering of this enum should not be altered because the
 * values are exposed extern(C)ally via pg_isready.
 */

enum PGPing
{
    OK, /* server is accepting connections */
    REJECT, /* server is alive but rejecting connections */
    NO_RESPONSE, /* could not establish connection */
    NO_ATTEMPT /* connection not attempted (bad params) */
}

/*
 * PGpipelineStatus - Current status of pipeline mode
 */
enum PGpipelineStatus
{
    OFF,
    ON,
    ABORTED
}

/* PGconn encapsulates a connection to the backend.
 * The contents of this struct are not supposed to be known to applications.
 */
struct PGconn;

/* PGresult encapsulates the result of a query (or more precisely, of a single
 * SQL command --- a query string given to PQsendQuery can contain multiple
 * commands and thus return multiple PGresult objects).
 * The contents of this struct are not supposed to be known to applications.
 */
struct PGresult;

/* PGcancel encapsulates the information needed to cancel a running
 * query on an existing connection.
 * The contents of this struct are not supposed to be known to applications.
 */
struct PGcancel;

/* PGnotify represents the occurrence of a NOTIFY message.
 * Ideally this would be an opaque typedef, but it's so simple that it's
 * unlikely to change.
 * NOTE: in Postgres 6.4 and later, the be_pid is the notifying backend's,
 * whereas in earlier versions it was always your own backend's PID.
 */
struct PGnotify
{
    char* relname; /* notification condition name */
    int be_pid; /* process ID of notifying server process */
    char* extra; /* notification parameter */
    /* Fields below here are private to libpq; apps should not use 'em */
    PGnotify* next; /* list link */
}

alias pqbool = bool;

static assert(pqbool.sizeof == 1, "use char instead bool");

struct PQprintOpt
{
    pqbool header; /* print output field headings and row count */
    pqbool align_; /* fill align the fields */
    pqbool standard; /* old brain dead format */
    pqbool html3; /* output html tables */
    pqbool expanded; /* expand tables */
    pqbool pager; /* use pager for output if needed */
    char* fieldSep; /* field separator */
    char* tableOpt; /* insert to HTML <table ...> */
    char* caption; /* HTML <caption> */
    char** fieldName; /* null terminated array of replacement field
								 * names */
}

/* ----------------
 * Structure for the conninfo parameter definitions returned by PQconndefaults
 * or PQconninfoParse.
 *
 * All fields except "val" point at static strings which must not be altered.
 * "val" is either NULL or a malloc'd current-value string.  PQconninfoFree()
 * will release both the val strings and the PQconninfoOption array itself.
 * ----------------
 */
struct PQconninfoOption
{
    char* keyword; /* The keyword of the option			*/
    char* envvar; /* Fallback environment variable name	*/
    char* compiled; /* Fallback compiled in default value	*/
    char* val; /* Option's current value, or NULL		 */
    char* label; /* Label for field in connect dialog	*/
    char* dispchar; /* Indicates how to display this field in a
								 * connect dialog. Values are: "" Display
								 * entered value as is "*" Password field -
								 * hide value "D"  Debug option - don't show
								 * by default */
    int dispsize; /* Field size in characters for dialog	*/
}

/* ----------------
 * PQArgBlock -- structure for PQfn() arguments
 * ----------------
 */
struct PQArgBlock
{
    int len;
    int isint;
    U u;

    static union U
    {
        int* ptr; /* can't use void (dec compiler barfs)	 */
        int integer;
    }
}

/* ----------------
 * PGresAttDesc -- Data about a single attribute (column) of a query result
 * ----------------
 */
struct PGresAttDesc
{
    char* name; /* column name */
    Oid tableid; /* source table, if known */
    int columnid; /* source column, if known */
    int format; /* format code for value (text/binary) */
    Oid typid; /* type id */
    int typlen; /* type size */
    int atttypmod; /* type-specific modifier info */
}

extern (C) nothrow
{
    /* Function types for notice-handling callbacks */
    alias PQnoticeReceiver = void function(void* arg, const PGresult* res);
    alias PQnoticeProcessor = void function(void* arg, const(char)* message);
    alias pgthreadlock_t = void function(int acquire);
    alias PQsslKeyPassHook_OpenSSL_type = int function(char* buf, int size, PGconn* conn);
}

// libpq-fs.h

enum INV_WRITE = 0x0002_0000;
enum INV_READ = 0x0004_0000;

// pg_type_d.h

enum TypeRelationId = 1247;
enum TypeRelation_Rowtype_Id = 71;

enum Anum_pg_type_oid = 1;
enum Anum_pg_type_typname = 2;
enum Anum_pg_type_typnamespace = 3;
enum Anum_pg_type_typowner = 4;
enum Anum_pg_type_typlen = 5;
enum Anum_pg_type_typbyval = 6;
enum Anum_pg_type_typtype = 7;
enum Anum_pg_type_typcategory = 8;
enum Anum_pg_type_typispreferred = 9;
enum Anum_pg_type_typisdefined = 10;
enum Anum_pg_type_typdelim = 11;
enum Anum_pg_type_typrelid = 12;
enum Anum_pg_type_typsubscript = 13;
enum Anum_pg_type_typelem = 14;
enum Anum_pg_type_typarray = 15;
enum Anum_pg_type_typinput = 16;
enum Anum_pg_type_typoutput = 17;
enum Anum_pg_type_typreceive = 18;
enum Anum_pg_type_typsend = 19;
enum Anum_pg_type_typmodin = 20;
enum Anum_pg_type_typmodout = 21;
enum Anum_pg_type_typanalyze = 22;
enum Anum_pg_type_typalign = 23;
enum Anum_pg_type_typstorage = 24;
enum Anum_pg_type_typnotnull = 25;
enum Anum_pg_type_typbasetype = 26;
enum Anum_pg_type_typtypmod = 27;
enum Anum_pg_type_typndims = 28;
enum Anum_pg_type_typcollation = 29;
enum Anum_pg_type_typdefaultbin = 30;
enum Anum_pg_type_typdefault = 31;
enum Anum_pg_type_typacl = 32;

enum Natts_pg_type = 32;

/*
 * macros for values of poor-mans-enumerated-type columns
 */
enum TYPTYPE_BASE = 'b'; /* base type (ordinary scalar type) */
enum TYPTYPE_COMPOSITE = 'c'; /* composite (e.g., table's rowtype) */
enum TYPTYPE_DOMAIN = 'd'; /* domain over another type */
enum TYPTYPE_ENUM = 'e'; /* enumerated type */
enum TYPTYPE_MULTIRANGE = 'm'; /* multirange type */
enum TYPTYPE_PSEUDO = 'p'; /* pseudo-type */
enum TYPTYPE_RANGE = 'r'; /* range type */

enum TYPCATEGORY_INVALID = '\0' /* not an allowed category */ ;
enum TYPCATEGORY_ARRAY = 'A';
enum TYPCATEGORY_BOOLEAN = 'B';
enum TYPCATEGORY_COMPOSITE = 'C';
enum TYPCATEGORY_DATETIME = 'D';
enum TYPCATEGORY_ENUM = 'E';
enum TYPCATEGORY_GEOMETRIC = 'G';
enum TYPCATEGORY_NETWORK = 'I'; /* think INET */
enum TYPCATEGORY_NUMERIC = 'N';
enum TYPCATEGORY_PSEUDOTYPE = 'P';
enum TYPCATEGORY_RANGE = 'R';
enum TYPCATEGORY_STRING = 'S';
enum TYPCATEGORY_TIMESPAN = 'T';
enum TYPCATEGORY_USER = 'U';
enum TYPCATEGORY_BITSTRING = 'V'; /* er ... "varbit"? */
enum TYPCATEGORY_UNKNOWN = 'X';

enum TYPALIGN_CHAR = 'c'; /* char alignment (i.e. unaligned) */
enum TYPALIGN_SHORT = 's'; /* short alignment (typically 2 bytes) */
enum TYPALIGN_INT = 'i'; /* int alignment (typically 4 bytes) */
enum TYPALIGN_DOUBLE = 'd'; /* double alignment (often 8 bytes) */

enum TYPSTORAGE_PLAIN = 'p'; /* type not prepared for toasting */
enum TYPSTORAGE_EXTERNAL = 'e'; /* toastable, don't try to compress */
enum TYPSTORAGE_EXTENDED = 'x'; /* fully toastable */
enum TYPSTORAGE_MAIN = 'm'; /* like 'x' but try to store inline */

/*
 * Backwards compatibility for ancient random spellings of pg_type OID macros.
 * Don't use these names in new code.
 */
enum CASHOID = MONEYOID;
enum LSNOID = PG_LSNOID;

enum BOOLOID = 16;
enum BYTEAOID = 17;
enum CHAROID = 18;
enum NAMEOID = 19;
enum INT8OID = 20;
enum INT2OID = 21;
enum INT2VECTOROID = 22;
enum INT4OID = 23;
enum REGPROCOID = 24;
enum TEXTOID = 25;
enum OIDOID = 26;
enum TIDOID = 27;
enum XIDOID = 28;
enum CIDOID = 29;
enum OIDVECTOROID = 30;
enum JSONOID = 114;
enum XMLOID = 142;
enum PG_NODE_TREEOID = 194;
enum PG_NDISTINCTOID = 3361;
enum PG_DEPENDENCIESOID = 3402;
enum PG_MCV_LISTOID = 5017;
enum PG_DDL_COMMANDOID = 32;
enum XID8OID = 5069;
enum POINTOID = 600;
enum LSEGOID = 601;
enum PATHOID = 602;
enum BOXOID = 603;
enum POLYGONOID = 604;
enum LINEOID = 628;
enum FLOAT4OID = 700;
enum FLOAT8OID = 701;
enum UNKNOWNOID = 705;
enum CIRCLEOID = 718;
enum MONEYOID = 790;
enum MACADDROID = 829;
enum INETOID = 869;
enum CIDROID = 650;
enum MACADDR8OID = 774;
enum ACLITEMOID = 1033;
enum BPCHAROID = 1042;
enum VARCHAROID = 1043;
enum DATEOID = 1082;
enum TIMEOID = 1083;
enum TIMESTAMPOID = 1114;
enum TIMESTAMPTZOID = 1184;
enum INTERVALOID = 1186;
enum TIMETZOID = 1266;
enum BITOID = 1560;
enum VARBITOID = 1562;
enum NUMERICOID = 1700;
enum REFCURSOROID = 1790;
enum REGPROCEDUREOID = 2202;
enum REGOPEROID = 2203;
enum REGOPERATOROID = 2204;
enum REGCLASSOID = 2205;
enum REGCOLLATIONOID = 4191;
enum REGTYPEOID = 2206;
enum REGROLEOID = 4096;
enum REGNAMESPACEOID = 4089;
enum UUIDOID = 2950;
enum PG_LSNOID = 3220;
enum TSVECTOROID = 3614;
enum GTSVECTOROID = 3642;
enum TSQUERYOID = 3615;
enum REGCONFIGOID = 3734;
enum REGDICTIONARYOID = 3769;
enum JSONBOID = 3802;
enum JSONPATHOID = 4072;
enum TXID_SNAPSHOTOID = 2970;
enum PG_SNAPSHOTOID = 5038;
enum INT4RANGEOID = 3904;
enum NUMRANGEOID = 3906;
enum TSRANGEOID = 3908;
enum TSTZRANGEOID = 3910;
enum DATERANGEOID = 3912;
enum INT8RANGEOID = 3926;
enum INT4MULTIRANGEOID = 4451;
enum NUMMULTIRANGEOID = 4532;
enum TSMULTIRANGEOID = 4533;
enum TSTZMULTIRANGEOID = 4534;
enum DATEMULTIRANGEOID = 4535;
enum INT8MULTIRANGEOID = 4536;
enum RECORDOID = 2249;
enum RECORDARRAYOID = 2287;
enum CSTRINGOID = 2275;
enum ANYOID = 2276;
enum ANYARRAYOID = 2277;
enum VOIDOID = 2278;
enum TRIGGEROID = 2279;
enum EVENT_TRIGGEROID = 3838;
enum LANGUAGE_HANDLEROID = 2280;
enum INTERNALOID = 2281;
enum ANYELEMENTOID = 2283;
enum ANYNONARRAYOID = 2776;
enum ANYENUMOID = 3500;
enum FDW_HANDLEROID = 3115;
enum INDEX_AM_HANDLEROID = 325;
enum TSM_HANDLEROID = 3310;
enum TABLE_AM_HANDLEROID = 269;
enum ANYRANGEOID = 3831;
enum ANYCOMPATIBLEOID = 5077;
enum ANYCOMPATIBLEARRAYOID = 5078;
enum ANYCOMPATIBLENONARRAYOID = 5079;
enum ANYCOMPATIBLERANGEOID = 5080;
enum ANYMULTIRANGEOID = 4537;
enum ANYCOMPATIBLEMULTIRANGEOID = 4538;
enum PG_BRIN_BLOOM_SUMMARYOID = 4600;
enum PG_BRIN_MINMAX_MULTI_SUMMARYOID = 4601;
enum BOOLARRAYOID = 1000;
enum BYTEAARRAYOID = 1001;
enum CHARARRAYOID = 1002;
enum NAMEARRAYOID = 1003;
enum INT8ARRAYOID = 1016;
enum INT2ARRAYOID = 1005;
enum INT2VECTORARRAYOID = 1006;
enum INT4ARRAYOID = 1007;
enum REGPROCARRAYOID = 1008;
enum TEXTARRAYOID = 1009;
enum OIDARRAYOID = 1028;
enum TIDARRAYOID = 1010;
enum XIDARRAYOID = 1011;
enum CIDARRAYOID = 1012;
enum OIDVECTORARRAYOID = 1013;
enum PG_TYPEARRAYOID = 210;
enum PG_ATTRIBUTEARRAYOID = 270;
enum PG_PROCARRAYOID = 272;
enum PG_CLASSARRAYOID = 273;
enum JSONARRAYOID = 199;
enum XMLARRAYOID = 143;
enum XID8ARRAYOID = 271;
enum POINTARRAYOID = 1017;
enum LSEGARRAYOID = 1018;
enum PATHARRAYOID = 1019;
enum BOXARRAYOID = 1020;
enum POLYGONARRAYOID = 1027;
enum LINEARRAYOID = 629;
enum FLOAT4ARRAYOID = 1021;
enum FLOAT8ARRAYOID = 1022;
enum CIRCLEARRAYOID = 719;
enum MONEYARRAYOID = 791;
enum MACADDRARRAYOID = 1040;
enum INETARRAYOID = 1041;
enum CIDRARRAYOID = 651;
enum MACADDR8ARRAYOID = 775;
enum ACLITEMARRAYOID = 1034;
enum BPCHARARRAYOID = 1014;
enum VARCHARARRAYOID = 1015;
enum DATEARRAYOID = 1182;
enum TIMEARRAYOID = 1183;
enum TIMESTAMPARRAYOID = 1115;
enum TIMESTAMPTZARRAYOID = 1185;
enum INTERVALARRAYOID = 1187;
enum TIMETZARRAYOID = 1270;
enum BITARRAYOID = 1561;
enum VARBITARRAYOID = 1563;
enum NUMERICARRAYOID = 1231;
enum REFCURSORARRAYOID = 2201;
enum REGPROCEDUREARRAYOID = 2207;
enum REGOPERARRAYOID = 2208;
enum REGOPERATORARRAYOID = 2209;
enum REGCLASSARRAYOID = 2210;
enum REGCOLLATIONARRAYOID = 4192;
enum REGTYPEARRAYOID = 2211;
enum REGROLEARRAYOID = 4097;
enum REGNAMESPACEARRAYOID = 4090;
enum UUIDARRAYOID = 2951;
enum PG_LSNARRAYOID = 3221;
enum TSVECTORARRAYOID = 3643;
enum GTSVECTORARRAYOID = 3644;
enum TSQUERYARRAYOID = 3645;
enum REGCONFIGARRAYOID = 3735;
enum REGDICTIONARYARRAYOID = 3770;
enum JSONBARRAYOID = 3807;
enum JSONPATHARRAYOID = 4073;
enum TXID_SNAPSHOTARRAYOID = 2949;
enum PG_SNAPSHOTARRAYOID = 5039;
enum INT4RANGEARRAYOID = 3905;
enum NUMRANGEARRAYOID = 3907;
enum TSRANGEARRAYOID = 3909;
enum TSTZRANGEARRAYOID = 3911;
enum DATERANGEARRAYOID = 3913;
enum INT8RANGEARRAYOID = 3927;
enum INT4MULTIRANGEARRAYOID = 6150;
enum NUMMULTIRANGEARRAYOID = 6151;
enum TSMULTIRANGEARRAYOID = 6152;
enum TSTZMULTIRANGEARRAYOID = 6153;
enum DATEMULTIRANGEARRAYOID = 6155;
enum INT8MULTIRANGEARRAYOID = 6157;
enum CSTRINGARRAYOID = 1263;
