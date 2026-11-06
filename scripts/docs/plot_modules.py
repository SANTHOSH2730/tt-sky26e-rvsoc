"""Module placement map of the final layout (docs/images/floorplan_modules.png).
The netlist is flat, so each cell is labelled from the hierarchical names of the
nets it drives; cells driving unnamed nets take the majority label of their
neighbours (a few rounds of label propagation)."""
import collections, os, re
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.collections import PatchCollection
from matplotlib.patches import Rectangle

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # project root
rows = []
die = None
for line in open(f'{ROOT}/.work/place/insts.csv'):
    t = line.rstrip('\n').split(',')
    if t[0] == '#die':
        die = list(map(float, t[1:5])); continue
    name, master = t[0], t[1]
    x0, y0, x1, y1 = map(float, t[2:6])
    onet = t[6].replace('\\', '')
    inets = [n.replace('\\', '') for n in t[7].split('|') if n]
    rows.append(dict(name=name, master=master, box=(x0, y0, x1, y1), onet=onet, inets=inets))

GROUPS = [  # (label, colour)
    ('Register file (13 x 32 bit)', '#1f77b4'),
    ('CPU datapath (ALU, shifter, CSRs)', '#ff7f0e'),
    ('CPU fetch / decode / control', '#d62728'),
    ('Memory controller + QSPI', '#2ca02c'),
    ('Timer', '#9467bd'),
    ('UART TX + RX', '#e377c2'),
    ('Bus, GPIO, peripheral registers', '#8c564b'),
    ('Clock tree', '#17becf'),
    ('Unassigned logic / buffers', '#bcbd22'),
    ('Tap, fill, decap', '#e8e8e8'),
]
COL = dict(GROUPS)

def net_label(n):
    if not n or n.startswith('_') or n.startswith('net') or n.startswith('ANTENNA'):
        return None
    if n.startswith('clknet') or n == 'clk':
        return GROUPS[7][0]
    if n.startswith('i_tinyqv.cpu.i_core.i_registers'):
        return GROUPS[0][0]
    if n.startswith('i_tinyqv.cpu.i_core.'):
        return GROUPS[1][0]
    if n.startswith('i_tinyqv.cpu.'):
        return GROUPS[2][0]
    if n.startswith('i_tinyqv.mem.'):
        return GROUPS[3][0]
    if n.startswith('i_timer.'):
        return GROUPS[4][0]
    if n.startswith('i_uart_'):
        return GROUPS[5][0]
    return GROUPS[6][0]

FILL = re.compile(r'(tapvpwrvgnd|fill|decap)')
nets = {}
for r in rows:
    if FILL.search(r['master']):
        r['label'] = GROUPS[9][0]
        continue
    if 'clkbuf' in r['master'] or 'clkinv' in r['master'] and r['onet'].startswith('clknet'):
        r['label'] = GROUPS[7][0]
    else:
        r['label'] = net_label(r['onet'])
    if r['label'] and r['onet']:
        nets[r['onet']] = r['label']

for _ in range(10):
    changed = 0
    fan = collections.defaultdict(collections.Counter)  # net -> labels of its loads
    for r in rows:
        if r['label'] and r['label'] not in (GROUPS[9][0], GROUPS[7][0]):
            for n in r['inets']:
                fan[n][r['label']] += 1
    for r in rows:
        if r['label']:
            continue
        c = collections.Counter(nets[n] for n in r['inets'] if n in nets and nets[n] != GROUPS[7][0])
        c.update(fan.get(r['onet'], {}))
        if c:
            r['label'] = c.most_common(1)[0][0]
            if r['onet']:
                nets[r['onet']] = r['label']
            changed += 1
    if not changed:
        break
for r in rows:
    if not r['label']:
        r['label'] = GROUPS[8][0]

area = collections.Counter(); count = collections.Counter()
for r in rows:
    x0, y0, x1, y1 = r['box']
    area[r['label']] += (x1 - x0) * (y1 - y0); count[r['label']] += 1

fig, ax = plt.subplots(figsize=(16, 11.5), dpi=100)
for lab, col in GROUPS:
    patches = [Rectangle((r['box'][0], r['box'][1]), r['box'][2] - r['box'][0], r['box'][3] - r['box'][1])
               for r in rows if r['label'] == lab]
    ax.add_collection(PatchCollection(patches, facecolor=col, edgecolor='none'))
ax.add_patch(Rectangle((die[0], die[1]), die[2] - die[0], die[3] - die[1], fill=False, edgecolor='black', lw=1.5))
ax.set_xlim(die[0] - 2, die[2] + 2); ax.set_ylim(die[1] - 2, die[3] + 2)
ax.set_aspect('equal')
ax.set_xlabel('x (um)'); ax.set_ylabel('y (um)')
ax.set_title('tt_um_santhosh_rvsoc - cell placement by module (2x2 tiles, 334.88 x 225.76 um, sky130A)')
handles = [Rectangle((0, 0), 1, 1, facecolor=col, edgecolor='grey', lw=0.3) for _, col in GROUPS]
labels = [f'{lab}: {count[lab]} cells, {area[lab]:,.0f} um2' for lab, _ in GROUPS]
ax.legend(handles, labels, loc='upper center', bbox_to_anchor=(0.5, -0.07), ncol=2, fontsize=11, frameon=False)
fig.tight_layout()
os.makedirs(f'{ROOT}/docs/images', exist_ok=True)
fig.savefig(f'{ROOT}/docs/images/floorplan_modules.png', bbox_inches='tight', pad_inches=0.3)
for lab, _ in GROUPS:
    print(f'{lab:40s} {count[lab]:6d} {area[lab]:10.0f}')
