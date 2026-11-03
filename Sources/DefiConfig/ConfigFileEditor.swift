import Foundation

/// Edits a configuration file in place without losing comments, ordering, or
/// unknown tables, and validates the whole document before writing.
public enum ConfigFileEditingError: Error, Equatable, CustomStringConvertible, Sendable {
  case notUTF8
  case invalidConfiguration(String)
  case concurrentModification
  case readFailed(String)
  case writeFailed(String)

  public var description: String {
    switch self {
    case .notUTF8:
      "the configuration file is not valid UTF-8"
    case .invalidConfiguration(let message):
      message
    case .concurrentModification:
      "the configuration changed while it was being edited"
    case .readFailed(let message):
      "could not read the configuration: \(message)"
    case .writeFailed(let message):
      "could not write the configuration: \(message)"
    }
  }
}

public struct ConfigFileEditor: Sendable {
  public struct Change: Equatable, Sendable {
    public let table: String
    public let key: String
    /// A rendered TOML value, or `nil` to remove the key.
    public let value: String?

    public init(table: String, key: String, value: String?) {
      self.table = table
      self.key = key
      self.value = value
    }
  }

  /// Applies changes to in-memory source and decodes the result for validation.
  public static func applying(
    _ changes: [Change],
    to source: String
  ) throws -> (source: String, config: Config) {
    var document = LosslessTOMLDocument(source)
    for change in changes {
      document.set(table: change.table, key: change.key, value: change.value)
    }
    let rendered = document.render()
    do {
      return (rendered, try Config.decode(Data(rendered.utf8)))
    } catch let error as ConfigError {
      throw ConfigFileEditingError.invalidConfiguration(error.description)
    } catch {
      throw ConfigFileEditingError.invalidConfiguration(String(describing: error))
    }
  }

  /// Reads, edits, validates, and atomically writes the configuration file.
  /// The edit aborts instead of overwriting a file that changed after it was read.
  @discardableResult
  public static func edit(_ changes: [Change], at url: URL) throws -> Config {
    let fileManager = FileManager.default
    let baseData: Data?
    if fileManager.fileExists(atPath: url.path) {
      do {
        baseData = try Data(contentsOf: url)
      } catch {
        throw ConfigFileEditingError.readFailed(error.localizedDescription)
      }
    } else {
      baseData = nil
    }
    let baseSource: String?
    if let baseData {
      guard let source = String(data: baseData, encoding: .utf8) else {
        throw ConfigFileEditingError.notUTF8
      }
      baseSource = source
    } else {
      baseSource = nil
    }

    let (rendered, config) = try applying(changes, to: baseSource ?? "")
    // A new file should end with a newline; an existing file keeps its own style.
    var updatedSource = rendered
    if baseSource == nil, !updatedSource.hasSuffix("\n") {
      updatedSource += "\n"
    }
    let updatedData = Data(updatedSource.utf8)
    guard updatedData != (baseData ?? Data()) else { return config }

    let latestData: Data?
    do {
      latestData = fileManager.fileExists(atPath: url.path)
        ? try Data(contentsOf: url) : nil
    } catch {
      throw ConfigFileEditingError.readFailed(error.localizedDescription)
    }
    guard latestData == baseData else {
      throw ConfigFileEditingError.concurrentModification
    }

    do {
      try fileManager.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try updatedData.write(to: url, options: .atomic)
    } catch {
      throw ConfigFileEditingError.writeFailed(error.localizedDescription)
    }
    return config
  }
}
