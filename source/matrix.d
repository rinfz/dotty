module matrix;

import std.experimental.logger : info, warning, fatal;
import std.format : format;
import std.json : parseJSON, JSONValue, JSONException;
import std.net.curl : get, post, put;
import std.string : toLower, translate;
import core.stdc.stdlib : exit;

import config : Config;
import message : Message;

static immutable string[string] NULL_PARAMS;

class Matrix {
private:
    Config config;
    string userID, roomID, accessToken, nextBatch, filterID;
    int txID;

    string makeParamString(const string[string] params, char concat) {
        if (params.length == 0) {
            return "";
        }
        string result = "%s".format(concat);
        foreach (key, value; params) {
            result ~= "%s=%s&".format(key, value);
        }
        return result[0 .. $ - 1];
    }

    string buildUrl(string endpoint,
            const string[string] params = NULL_PARAMS, string apiVersion = "unstable") {
        string url = "%s/_matrix/client/%s/%s".format(this.config.address, apiVersion, endpoint);
        char concat = '?';

        if (this.accessToken.length) {
            url ~= "%caccess_token=%s".format(concat, this.accessToken);
            concat = '&';
        }

        string paramString = this.makeParamString(params, concat);
        if (paramString.length) {
            url ~= paramString;
        }

        return url;
    }

public:
    this(Config config) {
        this.config = config;
    }

    string getSymbol() {
        return this.config.commandSymbol;
    }

    string getUserID() {
        return this.userID;
    }

    void login()
    out {
        assert(this.accessToken.length > 0 && this.userID.length > 0);
    }
    do {
        string url = this.buildUrl("login");
        string data = `{
            "user": "%s",
            "password": "%s",
            "type": "m.login.password"
        }`.format(this.config.username, this.config.password);
        try {
            JSONValue response = parseJSON(post(url, data));
            this.accessToken = response["access_token"].str;
            this.userID = response["user_id"].str;
        } catch (JSONException e) {
            fatal("Error: Unable to login to the server!");
            exit(-1);
        }
        info("Successfully logged in");
    }

    void join()
    out {
        assert(this.roomID.length > 0);
    }
    do {
        try {
            // ok to inline the assoc array, this function is only called once
            string encodedRoom = translate(this.config.room, ['#' : "%23", ':' : "%3A"]);
            JSONValue response = parseJSON(post(this.buildUrl("join/%s".format(encodedRoom)), `{}`));
            this.roomID = response["room_id"].str;
        } catch (JSONException e) {
            fatal("Error: Failed to join the room: ", this.config.room);
            exit(-1);
        }
        info("Successfully joined the room: ", this.config.room);
    }

    void setMessageFilter() {
        string url = this.buildUrl("user/%s/filter".format(this.userID));
        string data = `{
            "account_data": {"types": ["m.room.message"]},
            "room": {"rooms": ["%s"]}
        }`.format(this.roomID);
        try {
            JSONValue response = parseJSON(post(url, data));
            this.filterID = response["filter_id"].str;
            info("Successfully set the message filter");
        } catch (JSONException e) {
            warning("WARNING: Unable to set the message filter, still continuing");
        }
    }

    Message[] extractMessages(JSONValue data) {
        Message[] result;
        try {
            auto roomData = data["rooms"]["join"];
            if (this.roomID in roomData) {
                JSONValue events = roomData[this.roomID]["timeline"]["events"];
                foreach (event; events.array) {
                    if ("body" in event["content"]) {
                        result ~= Message(event["content"]["body"].str.toLower,
                                        event["sender"].str, event["event_id"].str);
                    }
                }
            }
        } catch (JSONException e) {
            warning("WARNING: Unable to extract any messages");
        }
        return result;
    }

    JSONValue sync() {
        string[string] params = ["filter" : this.filterID];
        if (this.nextBatch.length > 0) {
            params["since"] = this.nextBatch;
        }
        string url = this.buildUrl("sync", params);
        try {
            JSONValue response = parseJSON(get(url));
            this.nextBatch = response["next_batch"].str;
            return response;
        } catch (JSONException e) {
            warning("WARNING: Sync failed");
            return `{}`.parseJSON;
        }
    }

    void markRead(const Message message) {
        string data = `{
            "m.fully_read": "%s",
            "m.read": "%s"
        }`.format(message.eventID, message.eventID);
        string url = this.buildUrl("rooms/%s/read_markers".format(this.roomID));
        post(url, data);
    }

    void sendMessage(string message, string type = "m.text") {
        string url = this.buildUrl("rooms/%s/send/m.room.message/%d".format(this.roomID, this.txID));
        string data = `{
            "body": "%s",
            "msgtype": "%s"
        }`.format(message, type);
        put(url, data);
        this.txID += 1;
    }
}