const std = @import("std");
const Sha256 = std.crypto.hash.sha2.Sha256;

pub fn hashReaders(reader: *std.Io.Reader) ![Sha256.digest_length]u8 {
    var hasher = Sha256.init(.{});
    var buf: [4096]u8 = undefined;
    while (true) {
        const n = try reader.readSliceShort(&buf);
        if (n == 0) break;
        hasher.update(buf[0..n]);
    }
    var digest: [Sha256.digest_length]u8 = undefined;
    hasher.final(&digest);
    return digest;
}

test "test hash empty" {
    const text = "";
    var reader = std.Io.Reader.fixed(text);
    const bytes = try hashReaders(&reader);
    try std.testing.expectEqualStrings("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", &std.fmt.bytesToHex(bytes, .lower));
}
test "test hash abc" {
    const text = "abc";
    var reader = std.Io.Reader.fixed(text);
    const bytes = try hashReaders(&reader);
    try std.testing.expectEqualStrings("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", &std.fmt.bytesToHex(bytes, .lower));
}
