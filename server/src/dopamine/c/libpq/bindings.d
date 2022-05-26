module dopamine.c.libpq.bindings;

import dopamine.c.libpq.types;

import core.stdc.stdio : FILE;

extern (C) nothrow:

/* === in fe-connect.c === */

/* make a new client connection to the backend */
/* Asynchronous (non-blocking) */
PGconn* PQconnectStart(const(char)* conninfo);
PGconn* PQconnectStartParams(const(const(char)*)* keywords,
    const(const(char)*)* values, int expand_dbname);
PostgresPollingStatusType PQconnectPoll(PGconn* conn);

/* Synchronous (blocking) */
PGconn* PQconnectdb(const(char)* conninfo);
PGconn* PQconnectdbParams(const(const(char)*)* keywords,
    const(const(char)*)* values, int expand_dbname);
PGconn* PQsetdbLogin(const(char)* pghost, const(char)* pgport,
    const(char)* pgoptions, const(char)* pgtty,
    const(char)* dbName,
    const(char)* login, const(char)* pwd);

/* close the current connection and free the PGconn data structure */
void PQfinish(PGconn* conn);

/* get info about connection options known to PQconnectdb */
PQconninfoOption* PQconndefaults();

/* parse connection options in same way as PQconnectdb */
PQconninfoOption* PQconninfoParse(const(char)* conninfo, char** errmsg);

/* return the connection options used by a live connection */
PQconninfoOption* PQconninfo(PGconn* conn);

/* free the data structure returned by PQconndefaults() or PQconninfoParse() */
void PQconninfoFree(PQconninfoOption* connOptions);

/*
 * close the current connection and reestablish a new one with the same
 * parameters
 */
/* Asynchronous (non-blocking) */
int PQresetStart(PGconn* conn);
PostgresPollingStatusType PQresetPoll(PGconn* conn);

/* Synchronous (blocking) */
void PQreset(PGconn* conn);

/* request a cancel structure */
PGcancel* PQgetCancel(PGconn* conn);

/* free a cancel structure */
void PQfreeCancel(PGcancel* cancel);

/* issue a cancel request */
int PQcancel(PGcancel* cancel, char* errbuf, int errbufsize);

/* backwards compatible version of PQcancel; not thread-safe */
int PQrequestCancel(PGconn* conn);

/* Accessor functions for PGconn objects */
char* PQdb(const(PGconn)* conn);
char* PQuser(const(PGconn)* conn);
char* PQpass(const(PGconn)* conn);
char* PQhost(const(PGconn)* conn);
char* PQhostaddr(const(PGconn)* conn);
char* PQport(const(PGconn)* conn);
char* PQtty(const(PGconn)* conn);
char* PQoptions(const(PGconn)* conn);
ConnStatusType PQstatus(const(PGconn)* conn);
PGTransactionStatusType PQtransactionStatus(const(PGconn)* conn);
const(char)* PQparameterStatus(const(PGconn)* conn,
    const(char)* paramName);
int PQprotocolVersion(const(PGconn)* conn);
int PQserverVersion(const(PGconn)* conn);
char* PQerrorMessage(const(PGconn)* conn);
int PQsocket(const(PGconn)* conn);
int PQbackendPID(const(PGconn)* conn);
PGpipelineStatus PQpipelineStatus(const(PGconn)* conn);
int PQconnectionNeedsPassword(const(PGconn)* conn);
int PQconnectionUsedPassword(const(PGconn)* conn);
int PQclientEncoding(const(PGconn)* conn);
int PQsetClientEncoding(PGconn* conn, const(char)* encoding);

/* SSL information functions */
int PQsslInUse(PGconn* conn);
void* PQsslStruct(PGconn* conn, const(char)* struct_name);
const(char)* PQsslAttribute(PGconn* conn, const(char)* attribute_name);
const(const(char)*)* PQsslAttributeNames(PGconn* conn);

/* Get the OpenSSL structure associated with a connection. Returns NULL for
 * unencrypted connections or if any other TLS library is in use. */
void* PQgetssl(PGconn* conn);

/* Tell libpq whether it needs to initialize OpenSSL */
void PQinitSSL(int do_init);

/* More detailed way to tell libpq whether it needs to initialize OpenSSL */
void PQinitOpenSSL(int do_ssl, int do_crypto);

/* Return true if GSSAPI encryption is in use */
int PQgssEncInUse(PGconn* conn);

/* Returns GSSAPI context if GSSAPI is in use */
void* PQgetgssctx(PGconn* conn);

/* Set verbosity for PQerrorMessage and PQresultErrorMessage */
PGVerbosity PQsetErrorVerbosity(PGconn* conn, PGVerbosity verbosity);

/* Set CONTEXT visibility for PQerrorMessage and PQresultErrorMessage */
PGContextVisibility PQsetErrorContextVisibility(PGconn* conn,
    PGContextVisibility show_context);

/* Override default notice handling routines */
PQnoticeReceiver PQsetNoticeReceiver(PGconn* conn,
    PQnoticeReceiver proc,
    void* arg);
PQnoticeProcessor PQsetNoticeProcessor(PGconn* conn,
    PQnoticeProcessor proc,
    void* arg);

/*
 *	   Used to set callback that prevents concurrent access to
 *	   non-thread safe functions that libpq needs.
 *	   The default implementation uses a libpq internal mutex.
 *	   Only required for multithreaded apps that use kerberos
 *	   both within their app and for postgresql connections.
 */
pgthreadlock_t PQregisterThreadLock(pgthreadlock_t newhandler);

/* === in fe-trace.c === */
void PQtrace(PGconn* conn, FILE* debug_port);
void PQuntrace(PGconn* conn);

/* flags controlling trace output: */
/* omit timestamps from each line */
enum PQTRACE_SUPPRESS_TIMESTAMPS = (1 << 0);
/* redact portions of some messages, for testing frameworks */
enum PQTRACE_REGRESS_MODE = (1 << 1);
void PQsetTraceFlags(PGconn* conn, int flags);

/* === in fe-exec.c === */

/* Simple synchronous query */
PGresult* PQexec(PGconn* conn, const(char)* query);
PGresult* PQexecParams(PGconn* conn,
    const(char)* command,
    int nParams,
    const Oid* paramTypes,
    const(const(char)*)* paramValues,
    const int* paramLengths,
    const int* paramFormats,
    int resultFormat);
PGresult* PQprepare(PGconn* conn, const(char)* stmtName,
    const(char)* query, int nParams,
    const Oid* paramTypes);
PGresult* PQexecPrepared(PGconn* conn,
    const(char)* stmtName,
    int nParams,
    const(const(char)*)* paramValues,
    const int* paramLengths,
    const int* paramFormats,
    int resultFormat);

/* Interface for multiple-result or asynchronous queries */
enum PQ_QUERY_PARAM_MAX_LIMIT = 65_535;

int PQsendQuery(PGconn* conn, const(char)* query);
int PQsendQueryParams(PGconn* conn,
    const(char)* command,
    int nParams,
    const Oid* paramTypes,
    const(const(char)*)* paramValues,
    const int* paramLengths,
    const int* paramFormats,
    int resultFormat);
int PQsendPrepare(PGconn* conn, const(char)* stmtName,
    const(char)* query, int nParams,
    const Oid* paramTypes);
int PQsendQueryPrepared(PGconn* conn,
    const(char)* stmtName,
    int nParams,
    const(const(char)*)* paramValues,
    const int* paramLengths,
    const int* paramFormats,
    int resultFormat);
int PQsetSingleRowMode(PGconn* conn);
PGresult* PQgetResult(PGconn* conn);

/* Routines for managing an asynchronous query */
int PQisBusy(PGconn* conn);
int PQconsumeInput(PGconn* conn);

/* Routines for pipeline mode management */
int PQenterPipelineMode(PGconn* conn);
int PQexitPipelineMode(PGconn* conn);
int PQpipelineSync(PGconn* conn);
int PQsendFlushRequest(PGconn* conn);

/* LISTEN/NOTIFY support */
PGnotify* PQnotifies(PGconn* conn);

/* Routines for copy in/out */
int PQputCopyData(PGconn* conn, const(char)* buffer, int nbytes);
int PQputCopyEnd(PGconn* conn, const(char)* errormsg);
int PQgetCopyData(PGconn* conn, char** buffer, int async);

/* Deprecated routines for copy in/out */
int PQgetline(PGconn* conn, char* string, int length);
int PQputline(PGconn* conn, const(char)* string);
int PQgetlineAsync(PGconn* conn, char* buffer, int bufsize);
int PQputnbytes(PGconn* conn, const(char)* buffer, int nbytes);
int PQendcopy(PGconn* conn);

/* Set blocking/nonblocking connection to the backend */
int PQsetnonblocking(PGconn* conn, int arg);
int PQisnonblocking(const(PGconn)* conn);
int PQisthreadsafe();
PGPing PQping(const(char)* conninfo);
PGPing PQpingParams(const(const(char)*)* keywords,
    const(const(char)*)* values, int expand_dbname);

/* Force the write buffer to be written (or at least try) */
int PQflush(PGconn* conn);

/*
 * "Fast path" interface --- not really recommended for application
 * use
 */
PGresult* PQfn(PGconn* conn,
    int fnid,
    int* result_buf,
    int* result_len,
    int result_is_int,
    const PQArgBlock* args,
    int nargs);

/* Accessor functions for PGresult objects */
ExecStatusType PQresultStatus(const PGresult* res);
char* PQresStatus(ExecStatusType status);
char* PQresultErrorMessage(const PGresult* res);
char* PQresultVerboseErrorMessage(const PGresult* res,
    PGVerbosity verbosity,
    PGContextVisibility show_context);
char* PQresultErrorField(const PGresult* res, int fieldcode);
int PQntuples(const PGresult* res);
int PQnfields(const PGresult* res);
int PQbinaryTuples(const PGresult* res);
char* PQfname(const PGresult* res, int field_num);
int PQfnumber(const PGresult* res, const(char)* field_name);
Oid PQftable(const PGresult* res, int field_num);
int PQftablecol(const PGresult* res, int field_num);
int PQfformat(const PGresult* res, int field_num);
Oid PQftype(const PGresult* res, int field_num);
int PQfsize(const PGresult* res, int field_num);
int PQfmod(const PGresult* res, int field_num);
char* PQcmdStatus(PGresult* res);
char* PQoidStatus(const PGresult* res); /* old and ugly */
Oid PQoidValue(const PGresult* res); /* new and improved */
char* PQcmdTuples(PGresult* res);
char* PQgetvalue(const PGresult* res, int tup_num, int field_num);
int PQgetlength(const PGresult* res, int tup_num, int field_num);
int PQgetisnull(const PGresult* res, int tup_num, int field_num);
int PQnparams(const PGresult* res);
Oid PQparamtype(const PGresult* res, int param_num);

/* Describe prepared statements and portals */
PGresult* PQdescribePrepared(PGconn* conn, const(char)* stmt);
PGresult* PQdescribePortal(PGconn* conn, const(char)* portal);
int PQsendDescribePrepared(PGconn* conn, const(char)* stmt);
int PQsendDescribePortal(PGconn* conn, const(char)* portal);

/* Delete a PGresult */
void PQclear(PGresult* res);

/* For freeing other alloc'd results, such as PGnotify structs */
void PQfreemem(void* ptr);

/* Error when no password was given. */
/* Note: depending on this is deprecated; use PQconnectionNeedsPassword(). */
enum PQnoPasswordSupplied = "fe_sendauth: no password supplied\n";

/* Create and manipulate PGresults */
PGresult* PQmakeEmptyPGresult(PGconn* conn, ExecStatusType status);
PGresult* PQcopyResult(const PGresult* src, int flags);
int PQsetResultAttrs(PGresult* res, int numAttributes, PGresAttDesc* attDescs);
void* PQresultAlloc(PGresult* res, size_t nBytes);
size_t PQresultMemorySize(const PGresult* res);
int PQsetvalue(PGresult* res, int tup_num, int field_num, char* value, int len);

/* Quoting strings before inclusion in queries. */
size_t PQescapeStringConn(PGconn* conn,
    char* to, const(char)* from, size_t length,
    int* error);
char* PQescapeLiteral(PGconn* conn, const(char)* str, size_t len);
char* PQescapeIdentifier(PGconn* conn, const(char)* str, size_t len);
ubyte* PQescapeByteaConn(PGconn* conn,
    const(ubyte)* from, size_t from_length,
    size_t* to_length);
ubyte* PQunescapeBytea(const ubyte* strtext,
    size_t* retbuflen);

/* These forms are deprecated! */
size_t PQescapeString(char* to, const(char)* from, size_t length);
ubyte* PQescapeBytea(const(ubyte)* from, size_t from_length,
    size_t* to_length);

void PQprint(FILE* fout, /* output stream */
    const PGresult* res,
    const PQprintOpt* ps); /* option structure */

void PQdisplayTuples(const PGresult* res,
    FILE* fp, /* where to send the output */
    int fillAlign, /* pad the fields with spaces */
    const(char)* fieldSep, /* field separator */
    int printHeader, /* display headers? */
    int quiet);

void PQprintTuples(const PGresult* res,
    FILE* fout, /* output stream */
    int PrintAttNames, /* print attribute names */
    int TerseOutput, /* delimiter bars */
    int colWidth); /* width of column, if 0, use
											 * variable width */

/* === in fe-lobj.c === */

/* Large-object access routines */
int lo_open(PGconn* conn, Oid lobjId, int mode);
int lo_close(PGconn* conn, int fd);
int lo_read(PGconn* conn, int fd, char* buf, size_t len);
int lo_write(PGconn* conn, int fd, const(char)* buf, size_t len);
int lo_lseek(PGconn* conn, int fd, int offset, int whence);
pg_int64 lo_lseek64(PGconn* conn, int fd, pg_int64 offset, int whence);
Oid lo_creat(PGconn* conn, int mode);
Oid lo_create(PGconn* conn, Oid lobjId);
int lo_tell(PGconn* conn, int fd);
pg_int64 lo_tell64(PGconn* conn, int fd);
int lo_truncate(PGconn* conn, int fd, size_t len);
int lo_truncate64(PGconn* conn, int fd, pg_int64 len);
int lo_unlink(PGconn* conn, Oid lobjId);
Oid lo_import(PGconn* conn, const(char)* filename);
Oid lo_import_with_oid(PGconn* conn, const(char)* filename, Oid lobjId);
int lo_export(PGconn* conn, Oid lobjId, const(char)* filename);

/* === in fe-misc.c === */

/* Get the version of the libpq library in use */
int PQlibVersion();

/* Determine length of multibyte encoded char at *s */
int PQmblen(const(char)* s, int encoding);

/* Same, but not more than the distance to the end of string s */
int PQmblenBounded(const(char)* s, int encoding);

/* Determine display length of multibyte encoded char at *s */
int PQdsplen(const(char)* s, int encoding);

/* Get encoding id from environment variable PGCLIENTENCODING */
int PQenv2encoding();

/* === in fe-auth.c === */

char* PQencryptPassword(const(char)* passwd, const(char)* user);
char* PQencryptPasswordConn(PGconn* conn, const(char)* passwd, const(char)* user, const(
        char)* algorithm);

/* === in encnames.c === */

int pg_char_to_encoding(const(char)* name);
const(char)* pg_encoding_to_char(int encoding);
int pg_valid_server_encoding_id(int encoding);

/* === in fe-secure-openssl.c === */

PQsslKeyPassHook_OpenSSL_type PQgetSSLKeyPassHook_OpenSSL();
void PQsetSSLKeyPassHook_OpenSSL(PQsslKeyPassHook_OpenSSL_type hook);
int PQdefaultSSLKeyPassHook_OpenSSL(char* buf, int size, PGconn* conn);
