import os
import odb
db = odb.dbDatabase.create()
odb.read_db(db, os.environ['ODB'])
block = db.getChip().getBlock()
dbu = block.getDbUnitsPerMicron()
die = block.getDieArea()
out = open(os.environ['OUT'], 'w')
out.write(f"#die,{die.xMin()/dbu},{die.yMin()/dbu},{die.xMax()/dbu},{die.yMax()/dbu}\n")
for inst in block.getInsts():
    m = inst.getMaster().getName()
    bb = inst.getBBox()
    onet = ''
    inets = []
    for it in inst.getITerms():
        n = it.getNet()
        if n is None or it.isSpecial():
            continue
        if it.isOutputSignal() and not onet:
            onet = n.getName()
        elif it.isInputSignal():
            inets.append(n.getName())
    out.write(f"{inst.getName()},{m},{bb.xMin()/dbu:.2f},{bb.yMin()/dbu:.2f},{bb.xMax()/dbu:.2f},{bb.yMax()/dbu:.2f},{onet},{'|'.join(inets[:6])}\n")
out.close()
print('done', block.getInsts().__len__())
