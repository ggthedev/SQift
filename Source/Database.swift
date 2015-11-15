//
//  Database.swift
//  SQift
//
//  Created by Dave Camp on 3/7/15.
//  Copyright © 2015 Nike. All rights reserved.
//

import Foundation

/// The `Database` class represents a single connection to a SQLite database. For more details about using multiple
/// database connections to improve concurrency, see <https://www.sqlite.org/isolation.html>.
public class Database {

    // MARK: - Helper Types

    /**
        Used to specify the path of the database for initialization.

        - OnDisk:    Creates an on-disk database: <https://www.sqlite.org/uri.html>.
        - InMemory:  Creates an in-memory database: <https://www.sqlite.org/inmemorydb.html#sharedmemdb>.
        - Temporary: Creates a temporary database: <https://www.sqlite.org/inmemorydb.html#temp_db>.
    */
    public enum DatabaseType {
        case OnDisk(String)
        case InMemory
        case Temporary

        /// Returns the path of the database.
        public var path: String {
            switch self {
            case .OnDisk(let path):
                return path
            case .InMemory:
                return ":memory:"
            case .Temporary:
                return ""
            }
        }
    }

    /**
        Used to declare the transaction behavior when executing a transaction.

        For more info about transactions, see <https://www.sqlite.org/lang_transaction.html>.
    */
    public enum TransactionType: String {
        case Deferred = "DEFERRED"
        case Immediate = "IMMEDIATE"
        case Exclusive = "EXCLUSIVE"
    }

    private typealias TraceCallback = @convention(block) UnsafePointer<Int8> -> Void

    // MARK: - Properties

    /// Returns the fileName of the database connection.
    /// For more details, please refer to <https://www.sqlite.org/c3ref/db_filename.html>.
    public var fileName: String { return String.fromCString(sqlite3_db_filename(handle, nil))! }

    /// Returns whether the database connection is readOnly.
    /// For more details, please refer to <https://www.sqlite.org/c3ref/stmt_readonly.html>.
    public var readOnly: Bool { return sqlite3_db_readonly(handle, nil) == 1 }

    /// Returns whether the database connection is threadSafe.
    /// For more details, please refer to <https://www.sqlite.org/c3ref/threadsafe.html>.
    public var threadSafe: Bool { return sqlite3_threadsafe() > 0 }

    /// Returns the last insert row id of the database connection.
    /// For more details, please refer to <https://www.sqlite.org/c3ref/last_insert_rowid.html>.
    public var lastInsertRowID: Int64 { return sqlite3_last_insert_rowid(handle) }

    /// Returns the number of changes for the most recently completed INSERT, UPDATE or DELETE statement.
    /// For more details, please refer to: <https://www.sqlite.org/c3ref/changes.html>.
    public var changes: Int { return Int(sqlite3_changes(handle)) }

    /// Returns the total number of changes for all INSERT, UPDATE or DELETE statements since the connection was opened.
    /// For more details, please refer to: <https://www.sqlite.org/c3ref/total_changes.html>.
    public var totalChanges: Int { return Int(sqlite3_total_changes(handle)) }

    var handle: COpaquePointer = nil

    private var traceCallback: TraceCallback?

    // MARK: - Initialization

    /**
        Initializes the `Database` connection with the specified database type and initialization flags.

        For more details, please refer to: <https://www.sqlite.org/c3ref/open.html>.

        - parameter databaseType:  The database type to initialize.
        - parameter readOnly:      Whether the database should be read-only.
        - parameter multiThreaded: Whether the database should be multi-threaded.
        - parameter sharedCache:   Whether the database should use a shared cache.

        - throws: An `Error` if SQLite encounters an error when opening the database connection.

        - returns: The new `Database` connection.
    */
    public convenience init(
        databaseType: DatabaseType = .InMemory,
        readOnly: Bool = false,
        multiThreaded: Bool = true,
        sharedCache: Bool = true)
        throws
    {
        var flags: Int32 = 0

        flags |= readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
        flags |= multiThreaded ? SQLITE_OPEN_NOMUTEX : SQLITE_OPEN_FULLMUTEX
        flags |= sharedCache ? SQLITE_OPEN_SHAREDCACHE : SQLITE_OPEN_PRIVATECACHE

        try self.init(databaseType: databaseType, flags: flags)
    }

    /**
        Initializes the `Database` connection with the specified database type and initialization flags.

        For more details, please refer to: <https://www.sqlite.org/c3ref/open.html>.

        - parameter databaseType: The database type to initialize.
        - parameter flags:        The bitmask flags to use when initializing the database.

        - throws: An `Error` if SQLite encounters an error when opening the database connection.

        - returns: The new `Database` connection.
    */
    public init(databaseType: DatabaseType, flags: Int32) throws {
        try check(sqlite3_open_v2(databaseType.path, &handle, flags, nil))
    }

    deinit {
        sqlite3_close_v2(handle)
    }

    // MARK: - Execution

    /**
        Prepares a `Statement` instance by compiling the SQL statement and binding the parameter values.

            let statement = try db.prepare("INSERT INTO cars(name, price) VALUES(?, ?)")

        For more details, please refer to documentation in the `Statement` class.

        - parameter SQL:        The SQL string to compile.
        - parameter parameters: The parameters to bind to the statement.

        - throws: An `Error` if SQLite encounters and error compiling the SQL statement or binding the parameters.

        - returns: The new `Statement` instance.
    */
    public func prepare(SQL: String, _ parameters: Bindable?...) throws -> Statement {
        let statement = try Statement(database: self, SQL: SQL)

        if !parameters.isEmpty {
            try statement.bind(parameters)
        }

        return statement
    }

    /**
        Prepares a `Statement` instance by compiling the SQL statement and binding the parameter values.

            let statement = try db.prepare("INSERT INTO cars(name, price) VALUES(?, ?)")

        For more details, please refer to documentation in the `Statement` class.

        - parameter SQL:        The SQL string to compile.
        - parameter parameters: A dictionary of key/value pairs to bind to the statement.

        - throws: An `Error` if SQLite encounters and error compiling the SQL statement or binding the parameters.

        - returns: The new `Statement` instance.
    */
    public func prepare(SQL: String, _ parameters: [String: Bindable?]) throws -> Statement {
        let statement = try Statement(database: self, SQL: SQL)

        if !parameters.isEmpty {
            try statement.bind(parameters)
        }

        return statement
    }

    /**
        Executes the SQL statement in a single-step by internally calling prepare, step and finalize.

            try db.execute("PRAGMA foreign_keys = true")
            try db.execute("PRAGMA journal_mode = WAL")

        For more details, please refer to: <https://www.sqlite.org/c3ref/exec.html>.

        - parameter SQL: The SQL string to execute.

        - throws: An `Error` if SQLite encounters and error when executing the SQL statement.
    */
    public func execute(SQL: String) throws {
        try check(sqlite3_exec(handle, SQL, nil, nil, nil))
    }

    /**
        Runs the SQL statement in a single-step by internally calling prepare, bind, step and finalize.

            try db.run("INSERT INTO cars(name) VALUES(?)", "Honda")
            try db.run("UPDATE cars SET price = ? WHERE name = ?", 27_999, "Honda")

        For more details, please refer to documentation in the `Statement` class.

        - parameter SQL:        The SQL string to run.
        - parameter parameters: The parameters to bind to the statement.

        - throws: An `Error` if SQLite encounters and error when running the SQL statement.
    */
    public func run(SQL: String, _ parameters: Bindable?...) throws {
        try prepare(SQL).bind(parameters).run()
    }

    /**
        Runs the SQL statement in a single-step by internally calling prepare, bind, step and finalize.

            try db.run("INSERT INTO cars(name) VALUES(:name)", [":name": "Honda"])
            try db.run("UPDATE cars SET price = :price WHERE name = :name", [":price": 27_999, ":name": "Honda"])

        For more details, please refer to documentation in the `Statement` class.

        - parameter SQL:        The SQL string to run.
        - parameter parameters: The parameters to bind to the statement.

        - throws: An `Error` if SQLite encounters and error when running the SQL statement.
    */
    public func run(SQL: String, _ parameters: [String: Bindable?]) throws {
        try prepare(SQL).bind(parameters).run()
    }

    /**
        Fetches the first `Row` from the database after running the SQL statement query.

        Fetching the first row of a query can be convenient in cases where you are attempting to SELECT a single
        row. For example, using a LIMIT filter of 1 would be an excellent candidate for a `fetch`.

            let row = try db.fetch("SELECT * FROM cars WHERE type = 'sedan' LIMIT 1")

        For more details, please refer to documentation in the `Statement` class.

        - parameter SQL:        The SQL string to run.
        - parameter parameters: The parameters to bind to the statement.

        - throws: An `Error` if SQLite encounters and error when running the SQL statement for fetching the `Row`.

        - returns: The first `Row` of the query.
    */
    public func fetch(SQL: String, _ parameters: Bindable?...) throws -> Row {
        return try prepare(SQL).bind(parameters).fetch()
    }

    /**
        Runs the SQL query against the database and returns the first column value of the first row.

        The `query` method is designed for extracting single values from SELECT and PRAGMA statements. For example,
        using a SELECT min, max, avg functions or querying the `synchronous` value of the database.

            let min: UInt = try db.query("SELECT avg(price) FROM cars WHERE price > ?", 40_000)
            let synchronous: Int = try db.query("PRAGMA synchronous")

        You MUST be careful when using this method. It force unwraps the `Binding` even if the binding value
        is `nil`. It is much safer to use the optional `query` counterpart method.

        For more details, please refer to documentation in the `Statement` class.

        - parameter SQL:        The SQL string to run.
        - parameter parameters: The parameters to bind to the statement.

        - throws: An `Error` if SQLite encounters and error in the prepare, bind, step or data extraction process.

        - returns: The first column value of the first row of the query.
    */
    public func query<T: Binding>(SQL: String, _ parameters: Bindable?...) throws -> T {
        return try prepare(SQL).bind(parameters).query()
    }

    /**
        Runs the SQL query against the database and returns the first column value of the first row.

        The `query` method is designed for extracting single values from SELECT and PRAGMA statements. For example,
        using a SELECT min, max, avg functions or querying the `synchronous` value of the database.

            let min: UInt? = try db.query("SELECT avg(price) FROM cars WHERE price > ?", 40_000)
            let synchronous: Int? = try db.query("PRAGMA synchronous")

        For more details, please refer to documentation in the `Statement` class.

        - parameter SQL:        The SQL string to run.
        - parameter parameters: The parameters to bind to the statement.

        - throws: An `Error` if SQLite encounters and error in the prepare, bind, step or data extraction process.

        - returns: The first column value of the first row of the query.
    */
    public func query<T: Binding>(SQL: String, _ parameters: Bindable?...) throws -> T? {
        return try prepare(SQL).bind(parameters).query()
    }

    /**
        Runs the SQL query against the database and returns the first column value of the first row.

        The `query` method is designed for extracting single values from SELECT and PRAGMA statements. For example,
        using a SELECT min, max, avg functions or querying the `synchronous` value of the database.

            let min: UInt = try db.query("SELECT avg(price) FROM cars WHERE price > :price", [":price": 40_000])

        You MUST be careful when using this method. It force unwraps the `Binding` even if the binding value
        is `nil`. It is much safer to use the optional `query` counterpart method.

        For more details, please refer to documentation in the `Statement` class.

        - parameter SQL:        The SQL string to run.
        - parameter parameters: A dictionary of key/value pairs to bind to the statement.

        - throws: An `Error` if SQLite encounters and error in the prepare, bind, step or data extraction process.

        - returns: The first column value of the first row of the query.
    */
    public func query<T: Binding>(SQL: String, _ parameters: [String: Bindable?]) throws -> T {
        return try prepare(SQL).bind(parameters).query()
    }

    /**
        Runs the SQL query against the database and returns the first column value of the first row.

        The `query` method is designed for extracting single values from SELECT and PRAGMA statements. For example,
        using a SELECT min, max, avg functions or querying the `synchronous` value of the database.

            let min: UInt? = try db.query("SELECT avg(price) FROM cars WHERE price > :price", [":price": 40_000])

        For more details, please refer to documentation in the `Statement` class.

        - parameter SQL:        The SQL string to run.
        - parameter parameters: A dictionary of key/value pairs to bind to the statement.

        - throws: An `Error` if SQLite encounters and error in the prepare, bind, step or data extraction process.

        - returns: The first column value of the first row of the query.
    */
    public func query<T: Binding>(SQL: String, _ parameters: [String: Bindable?]) throws -> T? {
        return try prepare(SQL).bind(parameters).query()
    }

    // MARK: - Transactions

    /**
        Executes the specified closure inside of a transaction.

        If an error occurs when running the transaction, it is automatically rolled back before throwing.

        For more details, please refer to: <https://www.sqlite.org/c3ref/exec.html>.

        - parameter transactionType: The transaction type.
        - parameter closure:         The logic to execute inside the transaction.

        - throws: An `Error` if SQLite encounters an error running the transaction.
    */
    public func transaction(transactionType: TransactionType = .Deferred, closure: Void throws -> Void) throws {
        try execute("BEGIN \(transactionType.rawValue) TRANSACTION")

        do {
            try closure()
            try execute("COMMIT")
        } catch {
            try execute("ROLLBACK")
            throw error
        }
    }

    /**
        Executes the specified closure inside of a savepoint.

        If an error occurs when running the savepoint, it is automatically rolled back before throwing.

        For more details, please refer to: <https://www.sqlite.org/lang_savepoint.html>.

        - parameter name:    The name of the savepoint.
        - parameter closure: The logic to execute inside the savepoint.

        - throws: An `Error` if SQLite encounters an error running the savepoint.
    */
    public func savepoint(var name: String, closure: Void throws -> Void) throws {
        name = name.sanitize()

        try execute("SAVEPOINT \(name)")

        do {
            try closure()
            try execute("RELEASE SAVEPOINT \(name)")
        } catch {
            try execute("ROLLBACK TO SAVEPOINT \(name)")
            throw error
        }
    }

    // MARK: - Attach Database

    /**
        Attaches another database with the specified name.

        For more details, please refer to: <https://www.sqlite.org/lang_attach.html>.

        - parameter databaseType: The database type to attach.
        - parameter name:         The name of the database being attached.

        - throws: An `Error` if SQLite encounters an error attaching the database.
    */
    public func attachDatabase(databaseType: DatabaseType, withName name: String) throws {
        try execute("ATTACH DATABASE \(databaseType.path.sanitize()) AS \(name.sanitize())")
    }

    /**
        Detaches a previously attached database connection.

        For more details, please refer to: <https://www.sqlite.org/lang_detach.html>.

        - parameter name: The name of the database connection to detach.

        - throws: An `Error` if SQLite encounters an error detaching the database.
    */
    public func detachDatabase(name: String) throws {
        try execute("DETACH DATABASE \(name.sanitize())")
    }

    // MARK: - Tracing

    /**
        Registers the callback with SQLite to be called each time a statement calls step.

        For more details, please refer to: <https://www.sqlite.org/c3ref/profile.html>.

        - parameter callback: The callback closure called when SQLite internally calls step on a statement.
    */
    public func trace(callback: (String -> Void)?) {
        guard let callback = callback else {
            sqlite3_trace(handle, nil, nil)
            traceCallback = nil
            return
        }

        traceCallback = { callback(String.fromCString($0)!) }
        let traceCallbackPointer = unsafeBitCast(traceCallback, UnsafeMutablePointer<Void>.self)

        sqlite3_trace(handle, { unsafeBitCast($0, TraceCallback.self)($1) }, traceCallbackPointer)
    }

    // MARK: - Internal - Check Result Code

    func check(code: Int32) throws -> Int32 {
        guard let error = Error(code: code, database: self) else { return code }
        throw error
    }
}