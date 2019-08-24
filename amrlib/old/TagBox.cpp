/*
** (c) 1996-2000 The Regents of the University of California (through
** E.O. Lawrence Berkeley National Laboratory), subject to approval by
** the U.S. Department of Energy.  Your use of this software is under
** license -- the license agreement is attached and included in the
** directory as license.txt or you may contact Berkeley Lab's Technology
** Transfer Department at TTD@lbl.gov.  NOTICE OF U.S. GOVERNMENT RIGHTS.
** The Software was developed under funding from the U.S. Government
** which consequently retains certain rights as follows: the
** U.S. Government has been granted for itself and others acting on its
** behalf a paid-up, nonexclusive, irrevocable, worldwide license in the
** Software to reproduce, prepare derivative works, and perform publicly
** and display publicly.  Beginning five (5) years after the date
** permission to assert copyright is obtained from the U.S. Department of
** Energy, and subject to any subsequent five (5) year renewals, the
** U.S. Government is granted for itself and others acting on its behalf
** a paid-up, nonexclusive, irrevocable, worldwide license in the
** Software to reproduce, prepare derivative works, distribute copies to
** the public, perform publicly and display publicly, and to permit
** others to do so.
*/


//
// $Id: TagBox.cpp,v 1.60 2001/09/24 19:10:03 lijewski Exp $
//
#include <winstd.H>

#if defined(BL_OLD_STL)
#include <stdlib.h>
#include <math.h>
#else
#include <cmath>
#include <cstdlib>
#endif

#include <algorithm>
#include <vector>

#include <TagBox.H>
#include <Geometry.H>
#include <ParallelDescriptor.H>
#include <ccse-mpi.H>
//
// Number of IntVects that can fit into m_CollateSpace
//
long TagBoxArray::m_CollateCount = TagBoxArray::ChunkSize;

//
// Static space used by collate().
//
IntVect* TagBoxArray::m_CollateSpace = new IntVect[TagBoxArray::ChunkSize];

void
TagBoxArray::BumpCollateSpace (long numtags)
{
    BL_ASSERT(TagBoxArray::m_CollateCount < numtags);

    do
    {
        TagBoxArray::m_CollateCount += TagBoxArray::ChunkSize;
    }
    while (TagBoxArray::m_CollateCount < numtags);

    delete [] TagBoxArray::m_CollateSpace;

    TagBoxArray::m_CollateSpace = new IntVect[TagBoxArray::m_CollateCount];
}

TagBox::TagBox () {}

TagBox::TagBox (const Box& bx,
                int        n)
    :
    BaseFab<TagBox::TagType>(bx,n)
{
    setVal(TagBox::CLEAR);
}

void
TagBox::resize (const Box& b, int ncomp)
{
    BaseFab<TagType>::resize(b,ncomp);
}

TagBox*
TagBox::coarsen (const IntVect& ratio)
{
    Box cbx(domain);
    cbx.coarsen(ratio);
    TagBox* crse = new TagBox(cbx);
    const Box& cbox = crse->box();
    Box b1(BoxLib::refine(cbox,ratio));

    const int* flo  = domain.loVect();
    const int* fhi  = domain.hiVect();
    const int* flen = domain.length().getVect();

    const int* clo  = cbox.loVect();
    const int* chi  = cbox.hiVect();
    const int* clen = cbox.length().getVect();

    const int* lo  = b1.loVect();
    const int* hi  = b1.hiVect();
    const int* len = b1.length().getVect();

    int longlen, dir;
    longlen = b1.longside(dir);

    TagType* fdat = dataPtr();
    TagType* cdat = crse->dataPtr();

    TagType* t = new TagType[longlen];
    for (int i = 0; i < longlen; i++)
        t[i] = TagBox::CLEAR;

    int klo = 0, khi = 0, jlo = 0, jhi = 0, ilo, ihi;
    D_TERM(ilo=flo[0]; ihi=fhi[0]; ,
           jlo=flo[1]; jhi=fhi[1]; ,
           klo=flo[2]; khi=fhi[2];)

#define IXPROJ(i,r) (((i)+(r)*std::abs(i))/(r) - std::abs(i))
#define IOFF(j,k,lo,len) D_TERM(0, +(j-lo[1])*len[0], +(k-lo[2])*len[0]*len[1])
#define JOFF(i,k,lo,len) D_TERM(i-lo[0], +0, +(k-lo[2])*len[0]*len[1])
#define KOFF(i,j,lo,len) D_TERM(i-lo[0], +(j-lo[1])*len[0], +0)
   //
   // hack
   //
   dir = 0;
   
   int ratiox = 1, ratioy = 1, ratioz = 1;
   D_TERM(ratiox = ratio[0];,
          ratioy = ratio[1];,
          ratioz = ratio[2];)

   int dummy_ratio = 1;

   if (dir == 0)
   {
      for (int k = klo; k <= khi; k++)
      {
          int kc = IXPROJ(k,ratioz);
          for (int j = jlo; j <= jhi; j++)
          {
              int jc = IXPROJ(j,ratioy);
              TagType* c = cdat + IOFF(jc,kc,clo,clen);
              const TagType* f = fdat + IOFF(j,k,flo,flen);
              //
              // Copy fine grid row of values into tmp array.
              //
              for (int i = ilo; i <= ihi; i++)
                  t[i-lo[0]] = f[i-ilo];

              for (int off = 0; off < ratiox; off++)
              {
                  for (int ic = 0; ic < clen[0]; ic++)
                  {
                      int i = ic*ratiox + off;
                      c[ic] = std::max(c[ic],t[i]);
                  }
              }
          }
      }
   }
   else if (dir == 1)
   {
      for (int k = klo; k <= khi; k++)
      {
          int kc = IXPROJ(k,dummy_ratio);
          for (int i = ilo; i <= ihi; i++)
          {
              int ic = IXPROJ(i,dummy_ratio);
              TagType* c = cdat + JOFF(ic,kc,clo,clen);
              const TagType* f = fdat + JOFF(i,k,flo,flen);
              //
              // Copy fine grid row of values into tmp array.
              //
              int strd = flen[0];
              for (int j = jlo; j <= jhi; j++)
                  t[j-lo[1]] = f[(j-jlo)*strd];

              for (int off = 0; off < dummy_ratio; off++)
              {
                  int jc = 0;
                  strd = clen[0];
                  for (int jcnt = 0; jcnt < clen[1]; jcnt++)
                  {
                      int j = jcnt*dummy_ratio + off;
                      c[jc] = std::max(c[jc],t[j]);
                      jc += strd;
                  }
              }
          }
      }
   }
   else
   {
       for (int j = jlo; j <= jhi; j++)
       {
           int jc = IXPROJ(j,dummy_ratio);
           for (int i = ilo; i <= ihi; i++)
           {
               int ic = IXPROJ(i,dummy_ratio);
               TagType* c = cdat + KOFF(ic,jc,clo,clen);
               const TagType* f = fdat + KOFF(i,j,flo,flen);
               //
               // Copy fine grid row of values into tmp array.
               //
               int strd = flen[0]*flen[1];
               for (int k = klo; k <= khi; k++)
                   t[k-lo[2]] = f[(k-klo)*strd];

               for (int off = 0; off < dummy_ratio; off++)
               {
                   int kc = 0;
                   strd = clen[0]*clen[1];
                   for (int kcnt = 0; kcnt < clen[2]; kcnt++)
                   {
                       int k = kcnt*dummy_ratio + off;
                       c[kc] = std::max(c[kc],t[k]);
                       kc += strd;
                   }
               }
           }
      }
   }

   delete [] t;

   return crse;

#undef ABS
#undef IXPROJ
#undef IOFF
#undef JOFF
#undef KOFF
}

void 
TagBox::buffer (int nbuff,
                int nwid)
{
    //
    // Note: this routine assumes cell with TagBox::SET tag are in
    // interior of tagbox (region = grow(domain,-nwid)).
    //
    Box inside(domain);
    inside.grow(-nwid);
    const int* inlo = inside.loVect();
    const int* inhi = inside.hiVect();
    int klo = 0, khi = 0, jlo = 0, jhi = 0, ilo, ihi;
    D_TERM(ilo=inlo[0]; ihi=inhi[0]; ,
           jlo=inlo[1]; jhi=inhi[1]; ,
           klo=inlo[2]; khi=inhi[2];)

    const int* len = domain.length().getVect();
    const int* lo = domain.loVect();
    int ni = 0, nj = 0, nk = 0;
    D_TERM(ni, =nj, =nk) = nbuff;
    TagType* d = dataPtr();

#define OFF(i,j,k,lo,len) D_TERM(i-lo[0], +(j-lo[1])*len[0] , +(k-lo[2])*len[0]*len[1])
   
    for (int k = klo; k <= khi; k++)
    {
        for (int j = jlo; j <= jhi; j++)
        {
            for (int i = ilo; i <= ihi; i++)
            {
                TagType* d_check = d + OFF(i,j,k,lo,len);
                if (*d_check == TagBox::SET)
                {
                    for (int k = -nk; k <= nk; k++)
                    {
                        for (int j = -nj; j <= nj; j++)
                        {
                            for (int i = -ni; i <= ni; i++)
                            {
                                TagType* dn = d_check+ D_TERM(i, +j*len[0], +k*len[0]*len[1]);
                                if (*dn !=TagBox::SET)
                                    *dn = TagBox::BUF;
                            }
                        }
                    }
                }
            }
        }
    }
#undef OFF
}

void 
TagBox::merge (const TagBox& src)
{
    //
    // Compute intersections.
    //
    if (domain.intersects(src.domain))
    {
        Box bx          = domain & src.domain;
        const int* dlo  = domain.loVect();
        const int* dlen = domain.length().getVect();
        const int* slo  = src.domain.loVect();
        const int* slen = src.domain.length().getVect();
        const int* lo   = bx.loVect();
        const int* hi   = bx.hiVect();

        const TagType* ds0 = src.dataPtr();
        TagType* dd0       = dataPtr();

        int klo = 0, khi = 0, jlo = 0, jhi = 0, ilo, ihi;
        D_TERM(ilo=lo[0]; ihi=hi[0]; ,
               jlo=lo[1]; jhi=hi[1]; ,
               klo=lo[2]; khi=hi[2];)

#define OFF(i,j,k,lo,len) D_TERM(i-lo[0], +(j-lo[1])*len[0] , +(k-lo[2])*len[0]*len[1])
      
        for (int k = klo; k <= khi; k++)
        {
            for (int j = jlo; j <= jhi; j++)
            {
                for (int i = ilo; i <= ihi; i++)
                {
                    const TagType* ds = ds0 + OFF(i,j,k,slo,slen);
                    if (*ds != TagBox::CLEAR)
                    {
                        TagType* dd = dd0 + OFF(i,j,k,dlo,dlen);
                        *dd = TagBox::SET;
                    }            
                }
            }
        }
    }
#undef OFF
}

int
TagBox::numTags () const
{
   int nt = 0;
   long t_long = domain.numPts();
   if (t_long>1024*1024*1024)
    BoxLib::Warning("t_long > 2^30");
   int len = static_cast<int>(t_long);
   const TagType* d = dataPtr();
   for (int n = 0; n < len; n++)
   {
      if (d[n] != TagBox::CLEAR)
          nt++;
   }
   return nt;
}

int
TagBox::numTags (const Box& b) const
{
   TagBox tempTagBox(b,1);
   tempTagBox.copy(*this);
   return tempTagBox.numTags();
}

int
TagBox::collate (IntVect* ar,
                 int      start) const
{
    BL_ASSERT(!(ar == 0));
    BL_ASSERT(start >= 0);
    //
    // Starting at given offset of array ar, enter location (IntVect) of
    // each tagged cell in tagbox.
    //
    int count        = 0;
    const int* len   = domain.length().getVect();
    const int* lo    = domain.loVect();
    const TagType* d = dataPtr();
    int ni = 1, nj = 1, nk = 1;
    D_TERM(ni = len[0]; , nj = len[1]; , nk = len[2];)

    for (int k = 0; k < nk; k++)
    {
        for (int j = 0; j < nj; j++)
        {
            for (int i = 0; i < ni; i++)
            {
                const TagType* dn = d + D_TERM(i, +j*len[0], +k*len[0]*len[1]);
                if (*dn != TagBox::CLEAR)
                {
                    ar[start++] = IntVect(D_DECL(lo[0]+i,lo[1]+j,lo[2]+k));
                    count++;
                }
            }
        }
    }
    return count;
}

Array<int>
TagBox::tags () const
{
    Array<int> ar(domain.numPts(), TagBox::CLEAR);

    const TagType* cptr = dataPtr();
    int*           iptr = ar.dataPtr();

    for (int i = 0; i < ar.size(); i++, cptr++, iptr++)
    {
        if (*cptr)
            *iptr = *cptr;
    }

    return ar;
}

void
TagBox::tags (const Array<int>& ar)
{
    BL_ASSERT(ar.size() == domain.numPts());

    TagType*   cptr = dataPtr();
    const int* iptr = ar.dataPtr();

    for (int i = 0; i < ar.size(); i++, cptr++, iptr++)
    {
        if (*iptr)
            *cptr = *iptr;
    }
}

TagBoxArray::TagBoxArray (const BoxArray& ba,
                          int             ngrow)
    :
    m_border(ngrow)
{
    BoxArray grownBoxArray(ba);
    grownBoxArray.grow(ngrow);
    define(grownBoxArray, 1, 0, Fab_allocate);
}

int
TagBoxArray::borderSize () const
{
    return m_border;
}

void 
TagBoxArray::buffer (int nbuf)
{
    if (!(nbuf == 0))
    {
        BL_ASSERT(nbuf <= m_border);
        for (MFIter fai(*this); fai.isValid(); ++fai)
        {
            get(fai).buffer(nbuf, m_border);
        } 
    }
}

void
TagBoxArray::mapPeriodic (const Geometry& geom)
{
    if (!geom.isAnyPeriodic()) return;

    FabArrayCopyDescriptor<TagBox> facd;

    FabArrayId        faid   = facd.RegisterFabArray(this);
    const int         MyProc = ParallelDescriptor::MyProc();
    const Box&        domain = geom.Domain();
    Array<IntVect>    pshifts(27);

    std::vector<FillBoxId> fillBoxId;
    std::vector<IntVect>   shifts;

    for (int i = 0; i < boxarray.size(); i++)
    {
        if (!domain.contains(boxarray[i]))
        {
            geom.periodicShift(domain, boxarray[i], pshifts);

            for (int iiv = 0; iiv < pshifts.size(); iiv++)
            {
                Box shiftbox(boxarray[i]);

                shiftbox.shift(pshifts[iiv]);

                for (int j = 0; j < boxarray.size(); j++)
                {
                    if (distributionMap[j] == MyProc)
                    {
                        if (shiftbox.intersects(boxarray[j]))
                        {
                            Box intbox = boxarray[j] & shiftbox;

                            intbox.shift(-pshifts[iiv]);

                            fillBoxId.push_back(facd.AddBox(faid,
                                                            intbox,
                                                            0,
                                                            i,
                                                            0,
                                                            0,
                                                            n_comp));

                            BL_ASSERT(fillBoxId.back().box() == intbox);
                            //
                            // Here we'll save the index into fabparray.
                            //
                            fillBoxId.back().FabIndex(j);
                            //
                            // Maintain a parallel array of IntVect shifts.
                            //
                            shifts.push_back(pshifts[iiv]);
                        }
                    }
                }
            }
        }
    }

    facd.CollectData();

    BL_ASSERT(fillBoxId.size() == shifts.size());

    TagBox src;

    for (int i = 0; i < fillBoxId.size(); i++)
    {
        BL_ASSERT(distributionMap[fillBoxId[i].FabIndex()] == MyProc);

        src.resize(fillBoxId[i].box(), n_comp);

        facd.FillFab(faid, fillBoxId[i], src);

        src.shift(shifts[i]);

        fabparray[fillBoxId[i].FabIndex()].merge(src);
    }
}

long
TagBoxArray::numTags () const 
{
   long ntag = 0;

   for (MFIter fai(*this); fai.isValid(); ++fai)
   {
      ntag += get(fai).numTags();
   }

   ParallelDescriptor::ReduceLongSum(ntag);

   return ntag;
}

//
// Used by collate().
//

struct IntVectComp
{
    bool operator () (const IntVect& lhs,
                      const IntVect& rhs) const
    {
        return lhs.lexLT(rhs);
    }
};

IntVect*
TagBoxArray::collate (long& numtags) const
{

    numtags = numTags();

    if (TagBoxArray::m_CollateCount < numtags)
        TagBoxArray::BumpCollateSpace(numtags);

    const int NGrids = fabparray.size();

    Array<int> sharedNTags(NGrids); // Shared numTags per grid.
    Array<int> startOffset(NGrids); // Start locations per grid.

    for (MFIter fai(*this); fai.isValid(); ++fai)
    {
        sharedNTags[fai.index()] = get(fai).numTags();
    }
    const DistributionMapping& dMap = DistributionMap();

    for (int i = 0; i < NGrids; ++i)
    {
         ParallelDescriptor::Bcast(&sharedNTags[i], 1, dMap[i]);
    }

    startOffset[0] = 0;

    for (int i = 1; i < NGrids; ++i)
    {
        startOffset[i] = startOffset[i-1] + sharedNTags[i-1];
    }
    //
    // Communicate all local points so all procs have the same global set.
    //
    for (MFIter fai(*this); fai.isValid(); ++fai)
    {
        get(fai).collate(TagBoxArray::m_CollateSpace, startOffset[fai.index()]);
    }
    //
    // Make sure can pass IntVect as array of ints.
    //
    BL_ASSERT(sizeof(IntVect) == BL_SPACEDIM * sizeof(int));

    for (int i = 0; i < NGrids; ++i)
    {
        int* iptr =
            reinterpret_cast<int*>(TagBoxArray::m_CollateSpace+startOffset[i]);

        ParallelDescriptor::Bcast(iptr,
                                  sharedNTags[i] * BL_SPACEDIM,
                                  dMap[i]);
    }
    //
    // Remove duplicate IntVects.
    //
    std::sort(m_CollateSpace, m_CollateSpace+numtags, IntVectComp());

    IntVect* end = std::unique(m_CollateSpace,m_CollateSpace+numtags);

    ptrdiff_t duplicates = (m_CollateSpace+numtags) - end;

    BL_ASSERT(duplicates >= 0);

    numtags -= duplicates;

    return m_CollateSpace;
}

void
TagBoxArray::setVal (const BoxDomain& bd,
                     TagBox::TagVal   val)
{
    for (MFIter fai(*this); fai.isValid(); ++fai)
    {
        for (BoxDomain::const_iterator bdi = bd.begin();
             bdi != bd.end();
             ++bdi)
        {
            if (fai.validbox().intersects(*bdi))
            {
                Box isect = *bdi & fai.validbox();

                get(fai).setVal(val,isect,0);
            }
        }
    }
}

void
TagBoxArray::setVal (const BoxArray& ba,
                     TagBox::TagVal  val)
{
    for (MFIter fai(*this); fai.isValid(); ++fai)
    {
        for (int j = 0; j < ba.size(); j++)
        {
            if (fai.validbox().intersects(ba[j]))
            {
                Box isect = fai.validbox() & ba[j];

                get(fai).setVal(val,isect,0);
            }
        }
    } 
}

void
TagBoxArray::coarsen (const IntVect & ratio)
{
    for (MFIter fai(*this); fai.isValid(); ++fai)
    {
        TagBox* tfine = fabparray.remove(fai.index());
        TagBox* tcrse = tfine->coarsen(ratio);
        fabparray.set(fai.index(),tcrse);
        delete tfine;
    }
    boxarray.coarsen(ratio);
    m_border = 0;
}
