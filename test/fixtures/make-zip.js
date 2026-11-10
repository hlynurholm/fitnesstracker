import zlib from "node:zlib";

// Builds a one-entry zip archive, like the "export original" download from Garmin Connect.
export function makeZip(name, bytes, { deflate = true } = {}) {
  const data = deflate ? zlib.deflateRawSync(bytes) : Buffer.from(bytes);
  const nameBuf = Buffer.from(name);
  const crc = zlib.crc32 ? zlib.crc32(bytes) : 0;
  const local = Buffer.alloc(30);
  local.writeUInt32LE(0x04034b50, 0); local.writeUInt16LE(20, 4); local.writeUInt16LE(deflate ? 8 : 0, 8);
  local.writeUInt32LE(crc, 14); local.writeUInt32LE(data.length, 18); local.writeUInt32LE(bytes.length, 22); local.writeUInt16LE(nameBuf.length, 26);
  const central = Buffer.alloc(46);
  central.writeUInt32LE(0x02014b50, 0); central.writeUInt16LE(20, 4); central.writeUInt16LE(20, 6); central.writeUInt16LE(deflate ? 8 : 0, 10);
  central.writeUInt32LE(crc, 16); central.writeUInt32LE(data.length, 20); central.writeUInt32LE(bytes.length, 24); central.writeUInt16LE(nameBuf.length, 28);
  central.writeUInt32LE(0, 42); // offset of the local header
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0); end.writeUInt16LE(1, 8); end.writeUInt16LE(1, 10);
  end.writeUInt32LE(central.length + nameBuf.length, 12); end.writeUInt32LE(local.length + nameBuf.length + data.length, 16);
  return new Uint8Array(Buffer.concat([local, nameBuf, data, central, nameBuf, end]));
}
