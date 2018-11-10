import std.json : JSONValue;
import std.stdio : writeln;
import std.typecons : tuple;

import config : Config, readConfig;
import matrix : Matrix;
import message : Message;

import plugins.core : Core;
import plugins.utils : callCommands, callNoPrompt;


void run(ref Matrix connection) {
    immutable string symbol = connection.getSymbol();
    auto plugins = tuple(new Core());

    connection.login();
    connection.join();
    connection.setMessageFilter();
    // initial sync
    connection.sync();

    while (true) {
        JSONValue data = connection.sync();
        Message[] messages = connection.extractMessages(data);
        immutable size_t messageCount = messages.length;
        if (messageCount == 0) {
            continue;
        }

        connection.markRead(messages[$ - 1]);
        foreach (ref message; messages) {
            if (message.sender == connection.getUserID()) {
                // ignore our own messages
                continue;
            }

            // TODO: pass messageCount to sendMessage, if it's more than
            // one, quote the original message in the reply

            foreach(ref plugin; plugins) {
                string response = callCommands(symbol, plugin, message);
                if (response.length > 0) {
                    connection.sendMessage(response);
                }

                // run generic command
                response = callNoPrompt(plugin, message);
                if (response.length > 0) {
                    connection.sendMessage(response);
                }
            }
        }
    }
}

void main() {
    Config config = new Config(readConfig("config.json"));
    Matrix connection = new Matrix(config);
    run(connection);
}