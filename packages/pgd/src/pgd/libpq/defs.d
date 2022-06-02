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

/// Set of Oid values that reprensent types adapted in an nnum
/// to make error reporting easier
enum TypeOid : Oid
{
    BOOL = 16,
    BYTEA = 17,
    CHAR = 18,
    NAME = 19,
    INT8 = 20,
    INT2 = 21,
    INT2VECTOR = 22,
    INT4 = 23,
    REGPROC = 24,
    TEXT = 25,
    OID = 26,
    TID = 27,
    XID = 28,
    CID = 29,
    OIDVECTOR = 30,
    JSON = 114,
    XML = 142,
    PG_NODE_TREE = 194,
    PG_NDISTINCT = 3361,
    PG_DEPENDENCIES = 3402,
    PG_MCV_LIST = 5017,
    PG_DDL_COMMAND = 32,
    XID8 = 5069,
    POINT = 600,
    LSEG = 601,
    PATH = 602,
    BOX = 603,
    POLYGON = 604,
    LINE = 628,
    FLOAT4 = 700,
    FLOAT8 = 701,
    UNKNOWN = 705,
    CIRCLE = 718,
    MONEY = 790,
    MACADDR = 829,
    INET = 869,
    CIDR = 650,
    MACADDR8 = 774,
    ACLITEM = 1033,
    BPCHAR = 1042,
    VARCHAR = 1043,
    DATE = 1082,
    TIME = 1083,
    TIMESTAMP = 1114,
    TIMESTAMPTZ = 1184,
    INTERVAL = 1186,
    TIMETZ = 1266,
    BIT = 1560,
    VARBIT = 1562,
    NUMERIC = 1700,
    REFCURSOR = 1790,
    REGPROCEDURE = 2202,
    REGOPER = 2203,
    REGOPERATOR = 2204,
    REGCLASS = 2205,
    REGCOLLATION = 4191,
    REGTYPE = 2206,
    REGROLE = 4096,
    REGNAMESPACE = 4089,
    UUID = 2950,
    PG_LSN = 3220,
    TSVECTOR = 3614,
    GTSVECTOR = 3642,
    TSQUERY = 3615,
    REGCONFIG = 3734,
    REGDICTIONARY = 3769,
    JSONB = 3802,
    JSONPATH = 4072,
    TXID_SNAPSHOT = 2970,
    PG_SNAPSHOT = 5038,
    INT4RANGE = 3904,
    NUMRANGE = 3906,
    TSRANGE = 3908,
    TSTZRANGE = 3910,
    DATERANGE = 3912,
    INT8RANGE = 3926,
    INT4MULTIRANGE = 4451,
    NUMMULTIRANGE = 4532,
    TSMULTIRANGE = 4533,
    TSTZMULTIRANGE = 4534,
    DATEMULTIRANGE = 4535,
    INT8MULTIRANGE = 4536,
    RECORD = 2249,
    RECORDARRAY = 2287,
    CSTRING = 2275,
    ANY = 2276,
    ANYARRAY = 2277,
    VOID = 2278,
    TRIGGER = 2279,
    EVENT_TRIGGER = 3838,
    LANGUAGE_HANDLER = 2280,
    INTERNAL = 2281,
    ANYELEMENT = 2283,
    ANYNONARRAY = 2776,
    ANYENUM = 3500,
    FDW_HANDLER = 3115,
    INDEX_AM_HANDLER = 325,
    TSM_HANDLER = 3310,
    TABLE_AM_HANDLER = 269,
    ANYRANGE = 3831,
    ANYCOMPATIBLE = 5077,
    ANYCOMPATIBLEARRAY = 5078,
    ANYCOMPATIBLENONARRAY = 5079,
    ANYCOMPATIBLERANGE = 5080,
    ANYMULTIRANGE = 4537,
    ANYCOMPATIBLEMULTIRANGE = 4538,
    PG_BRIN_BLOOM_SUMMARY = 4600,
    PG_BRIN_MINMAX_MULTI_SUMMARY = 4601,
    BOOLARRAY = 1000,
    BYTEAARRAY = 1001,
    CHARARRAY = 1002,
    NAMEARRAY = 1003,
    INT8ARRAY = 1016,
    INT2ARRAY = 1005,
    INT2VECTORARRAY = 1006,
    INT4ARRAY = 1007,
    REGPROCARRAY = 1008,
    TEXTARRAY = 1009,
    OIDARRAY = 1028,
    TIDARRAY = 1010,
    XIDARRAY = 1011,
    CIDARRAY = 1012,
    OIDVECTORARRAY = 1013,
    PG_TYPEARRAY = 210,
    PG_ATTRIBUTEARRAY = 270,
    PG_PROCARRAY = 272,
    PG_CLASSARRAY = 273,
    JSONARRAY = 199,
    XMLARRAY = 143,
    XID8ARRAY = 271,
    POINTARRAY = 1017,
    LSEGARRAY = 1018,
    PATHARRAY = 1019,
    BOXARRAY = 1020,
    POLYGONARRAY = 1027,
    LINEARRAY = 629,
    FLOAT4ARRAY = 1021,
    FLOAT8ARRAY = 1022,
    CIRCLEARRAY = 719,
    MONEYARRAY = 791,
    MACADDRARRAY = 1040,
    INETARRAY = 1041,
    CIDRARRAY = 651,
    MACADDR8ARRAY = 775,
    ACLITEMARRAY = 1034,
    BPCHARARRAY = 1014,
    VARCHARARRAY = 1015,
    DATEARRAY = 1182,
    TIMEARRAY = 1183,
    TIMESTAMPARRAY = 1115,
    TIMESTAMPTZARRAY = 1185,
    INTERVALARRAY = 1187,
    TIMETZARRAY = 1270,
    BITARRAY = 1561,
    VARBITARRAY = 1563,
    NUMERICARRAY = 1231,
    REFCURSORARRAY = 2201,
    REGPROCEDUREARRAY = 2207,
    REGOPERARRAY = 2208,
    REGOPERATORARRAY = 2209,
    REGCLASSARRAY = 2210,
    REGCOLLATIONARRAY = 4192,
    REGTYPEARRAY = 2211,
    REGROLEARRAY = 4097,
    REGNAMESPACEARRAY = 4090,
    UUIDARRAY = 2951,
    PG_LSNARRAY = 3221,
    TSVECTORARRAY = 3643,
    GTSVECTORARRAY = 3644,
    TSQUERYARRAY = 3645,
    REGCONFIGARRAY = 3735,
    REGDICTIONARYARRAY = 3770,
    JSONBARRAY = 3807,
    JSONPATHARRAY = 4073,
    TXID_SNAPSHOTARRAY = 2949,
    PG_SNAPSHOTARRAY = 5039,
    INT4RANGEARRAY = 3905,
    NUMRANGEARRAY = 3907,
    TSRANGEARRAY = 3909,
    TSTZRANGEARRAY = 3911,
    DATERANGEARRAY = 3913,
    INT8RANGEARRAY = 3927,
    INT4MULTIRANGEARRAY = 6150,
    NUMMULTIRANGEARRAY = 6151,
    TSMULTIRANGEARRAY = 6152,
    TSTZMULTIRANGEARRAY = 6153,
    DATEMULTIRANGEARRAY = 6155,
    INT8MULTIRANGEARRAY = 6157,
    CSTRINGARRAY = 1263,
}
