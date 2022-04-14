import {exec} from "child_process";
import util from "util";
import http from "http";
import https from "https";

const apiKey = (await util.promisify(exec)("syncthing cli config gui apikey get")).stdout.trim();

const sendRequest = (url, options, body) => new Promise((res, rej) => {
	const client = url.startsWith("https") ? https : http;
	const req = client.request(url, options, (result) => {
		const { statusCode } = result;

		result.setEncoding("utf8");
		let rawData = "";
		result.on("data", (chunk) => { rawData += chunk; });
		result.on("end", () => {
			if (statusCode < 200 || statusCode >= 300) {
				rej(rawData);
			}else {
				try {
					const parsedData = JSON.parse(rawData);
					res(parsedData);
				} catch (e) {
					rej(e);
				}
			}
		});
	}).on("error", (e) => {
		rej(e);
	});
	if (body) {
		req.write(body);
	}
	req.end();
});

const sendSyncthingRequest = (url) => sendRequest(url, {headers: {method: "GET", "X-API-Key": apiKey}});

const sendTelegramCommand = async (url, params) => {
	const token = process.env.TOKEN;
	const chatId = process.env.CHAT_ID;
	
	const res = await sendRequest(`https://api.telegram.org/bot${token}/${url}`, {
		method: "POST",
		headers: {
			"Content-Type": "application/json"
		},
	}, JSON.stringify({...params, chat_id: chatId}));
	if (!res.ok) {
		throw res;
	}
	return res.result;
};

// set commands
await sendTelegramCommand("setMyCommands", {commands: [
	{command: "status", description: "Get folder + device stats"},
]});

const folderStats = await sendSyncthingRequest("http://localhost:8384/rest/stats/folder");
const deviceStats = await sendSyncthingRequest("http://localhost:8384/rest/stats/device");
const systemErrors = (await sendSyncthingRequest("http://localhost:8384/rest/system/error")).errors;
const pendingFolders = await sendSyncthingRequest("http://localhost:8384/rest/cluster/pending/folders");
const pendingDevices = await sendSyncthingRequest("http://localhost:8384/rest/cluster/pending/devices");

const folders = await Promise.all((await sendSyncthingRequest("http://localhost:8384/rest/config/folders")).map(async (folder) => {
	const status = await sendSyncthingRequest(`http://localhost:8384/rest/db/status?folder=${folder.id}`);
	const stats = folderStats[folder.id];
	const errors = await sendSyncthingRequest(`http://localhost:8384/rest/folder/errors?folder=${folder.id}`);

	return {
		id: folder.id,
		path: folder.path,
		paused: folder.paused,
		globalBytes: status.globalBytes,
		receiveOnlyChangedBytes: status.receiveOnlyChangedBytes,
		pullErrors: status.pullErrors,
		stateChanged: new Date(status.stateChanged).getTime() > 0 ? new Date(status.stateChanged) : undefined,
		lastFileAt: stats.lastFile && stats.lastFile.at && new Date(stats.lastFile.at).getTime() > 0 ? new Date(stats.lastFile.at) : undefined,
		errors: errors.errors,
	};
}));

const devices = await Promise.all((await sendSyncthingRequest("http://localhost:8384/rest/config/devices")).map(async (device) => {
	const stats = deviceStats[device.deviceID];

	return {
		deviceID: device.deviceID,
		name: device.name,
		paused: device.paused,
		lastSeen: new Date(stats.lastSeen).getTime() > 0 ? new Date(stats.lastSeen) : undefined,
	}
}));

console.log({folders, devices, systemErrors, pendingFolders, pendingDevices});

const folderWithErrors = folders.map((folder) => ({
	folderErrors: [
		folder.paused ? "Paused" : [],
		folder.receiveOnlyChangedBytes > 0 ? `RECEIVE ONLY CHANGED ${folder.receiveOnlyChangedBytes}`: [],
		folder.pullErrors > 0 ? `PULL ERRORS ${folder.pullErrors}`: [],
		folder.errors ? `ERRORS (${JSON.stringify(folder.errors)})`: [],
		new Date().getTime() - folder.stateChanged.getTime() > 1000 * 60 * 60 * 24 * 7 ? `STATE CHANGED >7 days ago (${folder.stateChanged})` : [],
	].flat(),
	...folder,
}));

const global = {
	globalErrors: [
		systemErrors !== null ? JSON.stringify(systemErrors) : [],
		Object.entries(pendingFolders).length > 0 ? JSON.stringify(pendingFolders) : [],
		Object.entries(pendingDevices).length > 0 ? JSON.stringify(pendingDevices) : [],
	].flat(),
	sumGlobalBytes: folders.reduce((memo, {globalBytes}) => memo + globalBytes, 0),
};

const deviceWithErrors = devices.map((device) => ({
	deviceErrors: [
		device.paused ? "Paused" : [],
		device.lastSeen && new Date().getTime() - device.lastSeen.getTime() > 1000 * 60 * 60 * 24 * 7 ? `LAST SEEN >7 days ago (${device.lastSeen})` : [],
	].flat(),
	...device,
}));

const inError = folderWithErrors.some(({folderErrors}) => folderErrors.length > 0) || deviceWithErrors.some(({deviceErrors}) => deviceErrors.length > 0) || global.globalErrors.length > 0;

const updates = await sendTelegramCommand("getUpdates", {timeout: 0});

const statusMessage = updates.find(({message}) => message.text === "/status");

if (statusMessage) {
	// needs detailed status

	const text = `
${inError ? "<b>=======ERROR=======</b>\n" : ""}Folders:

${folderWithErrors.map(({path, globalBytes, lastFileAt, folderErrors}) => `
${path}:\n  ${(globalBytes / 10**9).toFixed(2)} GB\n  Changed ${((new Date().getTime() - lastFileAt.getTime()) / (1000 * 60 * 60 * 24)).toFixed(0)} day(s) ago\n  ${folderErrors.length > 0 ? "ERRORS!" : ""}
`).map((l) => l.trim()).join("\n")}

Devices:

${deviceWithErrors.map(({name, lastSeen, deviceErrors}) => `
${name}:\n  seen: ${lastSeen ? `${((new Date().getTime() - lastSeen.getTime()) / (1000 * 60 * 60 * 24)).toFixed(0)} day(s) ago` : "never"}${deviceErrors.length > 0 ? "\n  ERRORS!" : ""}

`).map((l) => l.trim()).join("\n")}

System:

${(global.sumGlobalBytes / 10 ** 9).toFixed(2)} GB
${global.globalErrors.length > 0 ? "ERRORS!" : ""}
	`.trim();

	await sendTelegramCommand("sendMessage", {text, parse_mode: "HTML"})

	// clear messages
	await sendTelegramCommand("getUpdates", {timeout: 0, offset: statusMessage.update_id + 1});
}
if (inError) {
	const folderErrors = folderWithErrors.filter(({folderErrors}) => folderErrors.length > 0).map(({path, folderErrors}) => `
		${path}: ${folderErrors.join("\n")};
	`.trim()).join("\n\n");

	const deviceErrors = deviceWithErrors.filter(({deviceErrors}) => deviceErrors.length > 0).map(({name, deviceErrors}) => `
		${name}: ${deviceErrors.join("\n")};
	`.trim()).join("\n\n");

	const globalErrors = global.globalErrors.join("\n");

	const errorText = `
FOLDER
${folderErrors}

Device
${deviceErrors}

GLOBAL
${globalErrors}
	`.trim();
	console.log(errorText)
	await sendTelegramCommand("sendMessage", {text: "ERRORS", parse_mode: "HTML"})
	await sendTelegramCommand("sendMessage", {text: errorText, parse_mode: "HTML"})
}
