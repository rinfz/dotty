import core.time : dur;
import core.thread : Thread;

import std.algorithm.searching : startsWith;
import std.json : JSONValue;
import std.stdio : writeln;
import std.string : stripLeft;
import std.typecons : tuple;

import config : Config, readConfig;
import db : makeDB;
import matrix : Matrix;
import message : Message;

import plugins.bash : Bash;
import plugins.core : Core;
import plugins.futurama : Futurama;
import plugins.log : Log;
import plugins.rate : Rate;
import plugins.simpsons : Simpsons;
import plugins.quote : Quote;
import plugins.utils : callCommands, callNoPrompt;


extern(C) {
    void NimMain();
}

void run(ref Matrix connection) {
    int waitDur = 0, iters = 0;
    immutable string symbol = connection.getSymbol();
    auto plugins = tuple(new Log(), new Core(), new Quote(), new Rate(),
                         new Simpsons(), new Futurama(), new Bash());

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
            // cap the wait duration at 5 secs
            if (waitDur < 5) {
                iters += 1;

                if (iters >= 500) {
                    // 500 is an arbitrary amount but should generally take a
                    // while to build up to in an active conversation
                    waitDur += 1;
                    iters = 0;
                }
            }

            Thread.sleep(dur!"seconds"(waitDur));
            continue;
        }

        // reset sleep duration vars
        iters = 0;
        waitDur = 0;

        connection.markRead(messages[$ - 1]);
        foreach (ref message; messages) {
            if (message.sender == connection.getUserID()) {
                // ignore our own messages
                continue;
            }

            string quote;
            if (messageCount > 1) {
                quote = message.text;
            }

            foreach(ref plugin; plugins) {
                string response = callCommands(symbol, plugin, connection.db, message);
                if (response.length > 0) {
                    if (response.startsWith("!!image ")) {
                        connection.sendImage(response.stripLeft("!!image "));
                    } else {
                        connection.sendMessage(response, "m.text", quote);
                    }
                }

                // run generic command
                // these are more generic so pass in the Matrix connection instance
                response = callNoPrompt(plugin, connection, message);
                if (response.length > 0) {
                    connection.sendMessage(response, "m.text", quote);
                }
            }
        }
    }
}

void main() {
    NimMain(); // init nim gc
    auto db = makeDB();
    Config config = new Config(readConfig("config.json"));
    Matrix connection = new Matrix(config, db);
    run(connection);
}
