"""Decoder for NRV DELTA (Samsung S5KRC1S, MGROUP mode) .dvs raw files.

Bit layout reverse-engineered from DELTA_SDK.dll PacketParser::S5KRC1SDataProcess
(Windows x64 build in github.com/nrvcorp/DELTA_SDK). One 32-bit word = bytes B0..B3
in file order.

  B0 bit7 = 1 : event word (two 8-pixel vertical groups in the current column)
      g   = ((B0 & 1) << 6) | (B1 >> 2)     7-bit row group, rows 8g..8g+7
      f   = (B0 >> 2) & 0x1f                offset of the second group
      pol1= B1 & 1, mask1 = B3              group g
      pol2= (B1>>1) & 1, mask2 = B2         group g+f (or g-f if column dir flag set)
      bit k of a mask -> y = 8*group + k.   polarity 0 = ON, 1 = OFF
  type = B0 & 0x7c:
      0x04 column : dir = B1>>7, x = ((B2 & 7) << 8) | B3
      0x08 time   : B1 bit7 = 0 -> high22 = ((B1&0x3f)<<16)|(B2<<8)|B3   (ms)
                    B1 bit7 = 1 -> low10  = ((B2&3)<<8)|B3                (us)
      0x0c frame end
  (B0 >> 1) & 1 = camera index (0 for single camera)
  0x7f.. words at file start = header/register dump.
"""
import numpy as np

W, H = 960, 720


def decode(path, ts_scale_hi=1000, ts_scale_lo=1):
    b = np.fromfile(path, dtype=np.uint8).reshape(-1, 4).astype(np.int64)
    B0, B1, B2, B3 = b[:, 0], b[:, 1], b[:, 2], b[:, 3]
    n = len(b)
    idx = np.arange(n)
    is_ev = B0 >= 0x80
    typ = np.where(is_ev, -1, B0 & 0x7C)
    hdr = B0 == 0x7F
    typ[hdr] = -2

    def ffill(mask, values, init):
        pos = np.where(mask, idx, -1)
        pos = np.maximum.accumulate(pos)
        out = np.where(pos >= 0, values[np.maximum(pos, 0)], init)
        return out

    is_col = typ == 0x04
    col_x = ffill(is_col, ((B2 & 7) << 8) | B3, -1)
    col_dir = ffill(is_col, B1 >> 7, 0)

    is_hi = (typ == 0x08) & (B1 < 0x80)
    is_lo = (typ == 0x08) & (B1 >= 0x80)
    hi = ffill(is_hi, ((B1 & 0x3F) << 16) | (B2 << 8) | B3, 0)
    lo = ffill(is_lo, ((B2 & 3) << 8) | B3, 0)
    t_us = hi * ts_scale_hi + lo * ts_scale_lo

    is_fe = typ == 0x0C
    frame = np.cumsum(is_fe)  # events after k-th frame-end belong to frame k

    e = np.where(is_ev)[0]
    g = ((B0[e] & 1) << 6) | (B1[e] >> 2)
    f = (B0[e] >> 2) & 0x1F
    g2 = np.where(col_dir[e] == 1, g - f, g + f)
    xs, ys, ps, ts, fs = [], [], [], [], []
    for grp, mask, pol in ((g, B3[e], B1[e] & 1), (g2, B2[e], (B1[e] >> 1) & 1)):
        for k in range(8):
            hit = ((mask >> k) & 1).astype(bool)
            sel = e[hit]
            xs.append(col_x[sel]); ys.append(grp[hit] * 8 + k); ps.append(pol[hit])
            ts.append(t_us[sel]); fs.append(frame[sel])
    x = np.concatenate(xs); y = np.concatenate(ys); p = np.concatenate(ps)
    t = np.concatenate(ts); fr = np.concatenate(fs)
    ok = (x >= 0) & (x < W) & (y >= 0) & (y < H)
    o = np.argsort(fr[ok], kind='stable')
    ev = np.rec.fromarrays([t[ok][o], x[ok][o], y[ok][o], p[ok][o], fr[ok][o]],
                           names='t,x,y,p,frame')
    stats = dict(words=n, event_words=int(is_ev.sum()), col_words=int(is_col.sum()),
                 frame_ends=int(is_fe.sum()), ts_words=int((typ == 0x08).sum()),
                 header_words=int(hdr.sum()), dropped_out_of_range=int((~ok).sum()))
    return ev, stats


if __name__ == '__main__':
    import sys
    ev, st = decode(sys.argv[1])
    print(st)
    print('events', len(ev), 'ON frac', float((ev.p == 0).mean()))
    print('t range us', int(ev.t.min()), int(ev.t.max()), 'duration s', (ev.t.max() - ev.t.min()) / 1e6)
    np.save(sys.argv[2] if len(sys.argv) > 2 else 'events.npy', ev)
