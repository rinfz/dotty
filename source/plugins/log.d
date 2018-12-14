module plugins.log;

import std.algorithm.searching : canFind;
import std.experimental.logger : info;

import d2sqlite3 : Statement;

import matrix : Matrix;
import message : Message;


class Log {
public:
  string noPrompt(ref Matrix connection, const ref Message message) {
    import std.stdio : writeln;
    // only log messages from users we care about - see config.json
    if (!connection.config.logIgnore.canFind(message.sender)) {
      Statement query = connection.db.prepare(
          "INSERT INTO messages (sender, room, message) VALUES (:sender, :room, :message)"
      );
      query.bind(":sender", message.sender);
      query.bind(":room", connection.config.room);
      query.bind(":message", message.text);
      query.execute();
      query.reset();
      info("Logged message from: ", message.sender);
    }
    return "";
  }
}
