const std = @import("std");
const webui = @import("webui");

pub fn main() !void {
    // Initialize windows
    const main_window = webui.newWindow();
    defer main_window.destroy();

    const profile_window = webui.newWindow();
    defer profile_window.destroy();

    // Set custom browser folder if needed (optional)
    // webui.setBrowserFolder("C:\\Program Files\\Google\\Chrome\\Application");

    // Check if browsers exist
    std.debug.print("Chrome exists: {}\n", .{webui.browserExist(.Chrome)});
    std.debug.print("Firefox exists: {}\n", .{webui.browserExist(.Firefox)});
    std.debug.print("Edge exists: {}\n", .{webui.browserExist(.Edge)});

    // Get the best browser available
    const best_browser = main_window.getBestBrowser();
    std.debug.print("Best browser: {}\n", .{best_browser});

    // Set up the main window with default profile
    main_window.setProfile("", "");

    // Set proxy for the main window (optional)
    // main_window.setProxy("http://proxy.example.com:8080");

    // Set custom browser parameters
    main_window.setCustomParameters("--disable-gpu --disable-dev-shm-usage");

    // Bind events
    _ = try main_window.bind("switch_profile", switchProfile);
    _ = try main_window.bind("delete_profile", deleteCurrentProfile);
    _ = try main_window.bind("show_info", showBrowserInfo);

    // Show main window
    try main_window.show("index.html");

    // Set up profile window with custom profile
    profile_window.setProfile("TestProfile", "");

    // Show profile window with different browser
    try profile_window.showBrowser("profile.html", .Firefox);
    // Wait for windows to close
    webui.wait();

    // Clean up profiles at the end
    main_window.deleteProfile();
    profile_window.deleteProfile();

    // Optionally delete all profiles
    // webui.deleteAllProfiles();
}

fn switchProfile(e: *webui.Event) void {
    // Get profile name from JavaScript
    const profile_name = e.getString();

    std.debug.print("Switching to profile: {s}\n", .{profile_name});

    // Note: In a real application, you would close and reopen the window
    // with the new profile since profiles can't be changed after show()
    e.returnString("Profile switch requested. Please restart the window.");
}
fn deleteCurrentProfile(e: *webui.Event) void {
    std.debug.print("Deleting current profile...\n", .{});

    // This will delete the profile folder when the window closes
    e.getWindow().deleteProfile();

    e.returnString("Profile will be deleted when window closes.");
}
fn showBrowserInfo(e: *webui.Event) void {
    var info_buffer: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&info_buffer);
    const writer = fbs.writer();

    writer.print("Browser Detection Info:\n", .{}) catch {};
    writer.print("Chrome: {}\n", .{webui.browserExist(.Chrome)}) catch {};
    writer.print("Firefox: {}\n", .{webui.browserExist(.Firefox)}) catch {};
    writer.print("Edge: {}\n", .{webui.browserExist(.Edge)}) catch {};
    writer.print("Safari: {}\n", .{webui.browserExist(.Safari)}) catch {};
    writer.print("Chromium: {}\n", .{webui.browserExist(.Chromium)}) catch {};
    writer.print("Best Browser: {}\n", .{e.getWindow().getBestBrowser()}) catch {};
    const written = fbs.getWritten();
    var null_terminated: [1025]u8 = undefined;
    @memcpy(null_terminated[0..written.len], written);
    null_terminated[written.len] = 0;

    e.returnString(null_terminated[0..written.len :0]);
}
