module dopamine.c.libpq.defs;

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
    ACTIVE /* unused; keep for awhile for backwards
								 * compatibility */
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
