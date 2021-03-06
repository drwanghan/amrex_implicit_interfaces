#undef  BL_LANG_CC
#ifndef BL_LANG_FORT
#define BL_LANG_FORT
#endif

#include "AMReX_REAL.H"
#include "AMReX_CONSTANTS.H"
#include "AMReX_SPACE.H"
#include "AMReX_BC_TYPES.H"
#include "AMReX_ArrayLim.H"

#include "DIFFUSION_F.H"

#if (AMREX_SPACEDIM==3)
#define SDIM 3
#elif (AMREX_SPACEDIM==2)
#define SDIM 2
#else
print *,"dimension bust"
stop
#endif
!
! note for standard viscoelastic update:
! 1. DA/Dt=0  or DQ/Dt=0
! 2. A^** = S A^* S^T   S=I+dt grad u
! 3. dA/dt = -(A-I)/lambda  or DQ/Dt=-Q/lambda
!
! for just the HOOP STRESS term for viscoelastic update:
! 1. DA/Dt=0  or DQ/Dt=0
! 2. A^**=S A^* S^T  S=1+dt u/r
!    dA/dt=2 dt u A/r
! 3. dA/dt= -(A-1)/lambda or DQ/Dt=-Q/lambda
!
! force term: div(mu H Q)/rho or div(mu H A)/rho  Q=A-I
! force term for just the hoop term is: 
!   u_t = -mu H Q/(rho r) or u_t = -mu H A/(rho r)
!
!ux,vx,wx,uy,vy,wy,uz,vz,wz
! grad u in cylindrical coordinates:
!
! S= (grad u + grad u^T)/2 
!
! grad u=| u_r  u_t/r-v/r  u_z  |
!        | v_r  v_t/r+u/r  v_z  |
!        | w_r  w_t/r      w_z  |
! in RZ:
! grad u=| u_r  0  u_z  |
!        | 0   u/r  0   |
!        | w_r  0  w_z  |
!
! S=
!   |u_r     (u_t/r+v_r-v/r)/2   (u_z+w_r)/2   |
!   | .      v_t/r+u/r           (v_z+w_t/r)/2 |
!   | .      .                   w_z           |
!
! note: v_r-v/r=r(v/r)_r
!
! 2S=
!
!   |2u_r     (u_t/r+v_r-v/r)   (u_z+w_r)   |
!   | .       2v_t/r+2u/r       (v_z+w_t/r) |
!   | .      .                    2w_z      |
!
! 
! div S = | (r S_11)_r/r + (S_12)_t/r - S_22/r  + (S_13)_z |
!         | (r S_21)_r/r + (S_22)_t/r + S_12/r  + (S_23)_z |
!         | (r S_31)_r/r + (S_32)_t/r +           (S_33)_z |
! 
! ur =     costheta u + sintheta v
! utheta = -sintheta u + costheta v
! 
! u = costheta ur - sintheta utheta
! v = sintheta ur + costheta utheta
!
! e.g. theta=pi/2  ur=0 
!   u=-utheta  v=0
! if constant viscosity:
! div u = (ru)_r/r + v_t/r + w_z= u_r + u/r +v_t/r + w_z=0
! (div u)_r=u_rr+u_r/r-u/r^2+v_tr/r-v_t/r^2+w_zr=0
! (div u)_t/r=u_rt/r+u_t/r^2+v_tt/r^2+w_zt/r=0
! (div u)_z=u_rz+u_z/r+v_tz/r+w_zz=0
!
! div(2 S)=
! |2u_rr+2u_r/r+u_tt/r^2+v_tr/r-v_t/r^2-2v_t/r^2-2u/r^2+u_zz+w_rz |
! |u_tr/r+v_rr+v_r/r-v_r/r+2v_tt/r^2+2u_t/r^2+u_t/r^2+v_r/r-v/r^2+v_zz+w_tz/r|
! |u_zr+u_z/r+w_rr+w_r/r+v_zt/r+w_tt/r^2 + 2w_zz |=
!
! |u_rr+u_r/r-u/r^2+u_tt/r^2-2v_t/r^2+u_zz |    
! |v_rr+v_r/r+v_tt/r^2+2u_t/r^2-v/r^2+v_zz |
! |w_rr+w_r/r+w_tt/r^2+w_zz                |
!
! compromise: 
!
! GU=| u_r       u_t/r  u_z  |
!    | v_r       v_t/r  v_z  |
!    | w_r       w_t/r  w_z  |
!
! hoop term 1st component:  -3 v_t/r^2 - 2 u/r^2
! hoop term 2nd component:   3 u_t/r^2 - v/r^2
! 
! If constant_viscosity==true:
! hoop term 1st component:  -2 v_t/r^2 - u/r^2
! hoop term 2nd component:   2 u_t/r^2 - v/r^2
! No coupling terms.
! Diagonal terms not multiplied by 2.
       subroutine FORT_HOOPIMPLICIT( &
         override_density, &
         gravity_normalized, & ! gravity_normalized>0 unless invert_gravity
         grav_dir, &
         force,DIMS(force), &
         tensor,DIMS(tensor), &
         thermal,DIMS(thermal), &
         recon,DIMS(recon), &
         solxfab,DIMS(solxfab), &
         solyfab,DIMS(solyfab), &
         solzfab,DIMS(solzfab), &
         xlo,dx, &
         uold,DIMS(uold), &
         unew,DIMS(unew), &
         lsnew,DIMS(lsnew), &
         den,DIMS(den), &  ! 1/density
         mu,DIMS(mu), &
         tilelo,tilehi, &
         fablo,fabhi, &
         bfact, &
         level, &
         finest_level, &
         visc_coef, &
         angular_velocity, &
         constant_viscosity, &
         update_state, &
         dt, &
         rzflag, &
         nmat, &
         nparts, &
         nparts_def, &
         im_solid_map, &
         ntensorMM, &
         nsolveMM)

       use probf90_module
       use global_utility_module 

       IMPLICIT NONE

       INTEGER_T, intent(in) :: override_density
       INTEGER_T, intent(in) :: grav_dir
       REAL_T, intent(in) :: gravity_normalized
 
       INTEGER_T, intent(in) :: nmat
       INTEGER_T, intent(in) :: nparts
       INTEGER_T, intent(in) :: nparts_def
       INTEGER_T, intent(in) :: im_solid_map(nparts_def)
       INTEGER_T, intent(in) :: ntensorMM
       INTEGER_T, intent(in) :: nsolveMM
       INTEGER_T, intent(in) :: level
       INTEGER_T, intent(in) :: finest_level
       INTEGER_T, intent(in) :: rzflag
       REAL_T, intent(in) :: angular_velocity
       REAL_T, intent(in) :: visc_coef
       INTEGER_T, intent(in) :: constant_viscosity
       INTEGER_T, intent(in) :: update_state
       REAL_T, intent(in) :: dt
       INTEGER_T, intent(in) :: tilelo(SDIM),tilehi(SDIM)
       INTEGER_T, intent(in) :: fablo(SDIM),fabhi(SDIM)
       INTEGER_T :: growlo(3),growhi(3)
       INTEGER_T, intent(in) :: bfact
    
       INTEGER_T, intent(in) :: DIMDEC(force)
       INTEGER_T, intent(in) :: DIMDEC(tensor)
       INTEGER_T, intent(in) :: DIMDEC(thermal)
       INTEGER_T, intent(in) :: DIMDEC(recon)
       INTEGER_T, intent(in) :: DIMDEC(solxfab)
       INTEGER_T, intent(in) :: DIMDEC(solyfab)
       INTEGER_T, intent(in) :: DIMDEC(solzfab)
       INTEGER_T, intent(in) :: DIMDEC(uold)
       INTEGER_T, intent(in) :: DIMDEC(unew)
       INTEGER_T, intent(in) :: DIMDEC(lsnew)
       INTEGER_T, intent(in) :: DIMDEC(den)
       INTEGER_T, intent(in) :: DIMDEC(mu)

       REAL_T, intent(out) ::  force(DIMV(force),nsolveMM)
       REAL_T, intent(in) ::  tensor(DIMV(tensor),ntensorMM)
       REAL_T, intent(in) ::  thermal(DIMV(thermal),num_materials_scalar_solve)
       REAL_T, intent(in) ::  recon(DIMV(recon),nmat*ngeom_recon)
       REAL_T, intent(in) ::  solxfab(DIMV(solxfab),nparts_def*SDIM)
       REAL_T, intent(in) ::  solyfab(DIMV(solyfab),nparts_def*SDIM)
       REAL_T, intent(in) ::  solzfab(DIMV(solzfab),nparts_def*SDIM)
       REAL_T, intent(in) ::  uold(DIMV(uold),nsolveMM)
       REAL_T, intent(out) ::  unew(DIMV(unew),nsolveMM)
       REAL_T, intent(in) ::  lsnew(DIMV(lsnew),nmat*(SDIM+1))
       REAL_T, intent(in) ::  den(DIMV(den),nmat+1)
       REAL_T, intent(in) ::  mu(DIMV(mu),nmat+1)
       REAL_T, intent(in) ::  xlo(SDIM)
       REAL_T ::  xsten(-3:3,SDIM)
       REAL_T, intent(in) ::  dx(SDIM)

       INTEGER_T i,j,k,dir
       INTEGER_T im
       REAL_T un(nsolveMM)
       REAL_T unp1(nsolveMM)
       REAL_T RCEN
       REAL_T inverseden
       REAL_T mu_cell
       INTEGER_T vofcomp
       INTEGER_T nhalf
       REAL_T DTEMP,FWATER,liquid_temp
       INTEGER_T nsolve
       INTEGER_T ntensor
       REAL_T vt_over_r,ut_over_r
       REAL_T param1,param2,hoop_force_coef
       INTEGER_T ut_comp
       REAL_T temp_offset
       REAL_T gtemp_offset(SDIM)
       INTEGER_T partid,im_solid,partid_crit
       REAL_T LStest,LScrit

       nhalf=3

       if (num_materials_vel.ne.1) then
        print *,"num_materials_vel invalid"
        stop
       endif
       if ((num_materials_scalar_solve.ne.1).and. &
           (num_materials_scalar_solve.ne.nmat)) then
        print *,"num_materials_scalar_solve invalid"
        stop
       endif

       nsolve=SDIM
       if (nsolveMM.ne.nsolve*num_materials_vel) then
        print *,"nsolveMM invalid"
        stop
       endif
       ntensor=SDIM*SDIM
       if (ntensorMM.ne.ntensor*num_materials_vel) then
        print *,"ntensorMM invalid"
        stop
       endif
       if ((constant_viscosity.ne.0).and. &
           (constant_viscosity.ne.1)) then
        print *,"constant_viscosity invalid"
        stop
       endif
       if ((update_state.ne.0).and. &
           (update_state.ne.1)) then
        print *,"update_state invalid"
        stop
       endif
       if ((level.lt.0).or.(level.gt.finest_level)) then
        print *,"level invalid hoop implicit"
        stop
       endif
       if ((nparts.lt.0).or.(nparts.gt.nmat)) then
        print *,"nparts invalid FORT_HOOPIMPLICIT"
        stop
       endif
       if ((nparts_def.lt.1).or.(nparts_def.gt.nmat)) then
        print *,"nparts_def invalid FORT_HOOPIMPLICIT"
        stop
       endif

       if (bfact.lt.1) then
        print *,"bfact invalid8"
        stop
       endif
       if (nmat.ne.num_materials) then
        print *,"nmat invalid"
        stop
       endif

       if (rzflag.eq.0) then
        ! do nothing
       else if (rzflag.eq.1) then
        if (SDIM.ne.2) then
         print *,"dimension bust"
         stop
        endif
       else if (rzflag.eq.3) then
        ! do nothing
       else 
        print *,"rzflag invalid"
        stop
       endif
       if (num_state_base.ne.2) then
        print *,"num_state_base invalid"
        stop
       endif
       if ((grav_dir.lt.1).or.(grav_dir.gt.SDIM)) then
        print *,"gravity dir invalid hoopimplicit"
        stop
       endif

       if (angular_velocity.lt.zero) then
        print *,"angular_velocity cannot be negative"
        stop
       endif

       call checkbound(fablo,fabhi,DIMS(force),1,-1,42)
       call checkbound(fablo,fabhi,DIMS(tensor),0,-1,42)
       call checkbound(fablo,fabhi,DIMS(thermal),1,-1,1330)
       call checkbound(fablo,fabhi,DIMS(recon),1,-1,1330)
       call checkbound(fablo,fabhi,DIMS(solxfab),0,0,1330)
       call checkbound(fablo,fabhi,DIMS(solyfab),0,1,1330)
       call checkbound(fablo,fabhi,DIMS(solzfab),0,SDIM-1,1330)
       call checkbound(fablo,fabhi,DIMS(uold),1,-1,1330)
       call checkbound(fablo,fabhi,DIMS(unew),1,-1,1330)
       call checkbound(fablo,fabhi,DIMS(lsnew),1,-1,1251)
       call checkbound(fablo,fabhi,DIMS(den),1,-1,1330)
       call checkbound(fablo,fabhi,DIMS(mu),1,-1,1330)

       call growntilebox(tilelo,tilehi,fablo,fabhi,growlo,growhi,0) 

       do i=growlo(1),growhi(1)
       do j=growlo(2),growhi(2)
       do k=growlo(3),growhi(3)

        call gridsten_level(xsten,i,j,k,level,nhalf)

        do dir=1,SDIM
         un(dir)=uold(D_DECL(i,j,k),dir)
         unp1(dir)=uold(D_DECL(i,j,k),dir)
        enddo ! dir=1..sdim

        partid=0
        im_solid=0
        partid_crit=0

        do im=1,nmat
         if (is_lag_part(nmat,im).eq.1) then
          if (is_rigid(nmat,im).eq.1) then
           LStest=lsnew(D_DECL(i,j,k),im)
           if (is_prescribed(nmat,im).eq.1) then
            if (LStest.ge.zero) then
             if (im_solid.eq.0) then
              im_solid=im
              partid_crit=partid
              LScrit=LStest
             else if ((im_solid.ge.1).and.(im_solid.le.nmat)) then
              if (LStest.ge.LScrit) then
               im_solid=im
               partid_crit=partid
               LScrit=LStest
              endif
             else
              print *,"im_solid invalid 1"
              stop
             endif
            else if (LStest.lt.zero) then
             ! do nothing
            else
             print *,"LStest invalid"
             stop
            endif
           else if (is_prescribed(nmat,im).eq.0) then
            ! do nothing
           else
            print *,"is_prescribed(nmat,im) invalid"
            stop
           endif
          else if (is_rigid(nmat,im).eq.0) then
           ! do nothing
          else
           print *,"is_rigid(nmat,im) invalid"
           stop
          endif
          partid=partid+1
         else if (is_lag_part(nmat,im).eq.0) then
          if (is_rigid(nmat,im).eq.0) then
           ! do nothing
          else
           print *,"is_rigid invalid"
           stop
          endif
         else
          print *,"is_lag_part invalid"
          stop
         endif
        enddo ! im=1..nmat

        if (partid.ne.nparts) then
         print *,"partid invalid"
         stop
        endif

        inverseden=den(D_DECL(i,j,k),1)
        mu_cell=mu(D_DECL(i,j,k),1)
        if (inverseden.le.zero) then
         print *,"inverseden invalid"
         stop
        endif
        if (mu_cell.lt.zero) then
         print *,"mu_cell invalid"
         stop
        endif
 
        if ((im_solid.ge.1).and.(im_solid.le.nmat)) then
         if (im_solid_map(partid_crit+1)+1.ne.im_solid) then
          print *,"im_solid_map(partid_crit+1)+1.ne.im_solid"
          stop
         endif

         dir=1
         unp1(dir)=half*( &
            solxfab(D_DECL(i,j,k),partid_crit*SDIM+dir)+ &
            solxfab(D_DECL(i+1,j,k),partid_crit*SDIM+dir))
         dir=2
         unp1(dir)=half*( &
            solyfab(D_DECL(i,j,k),partid_crit*SDIM+dir)+ &
            solyfab(D_DECL(i,j+1,k),partid_crit*SDIM+dir))
         if (SDIM.eq.3) then
          dir=SDIM
          unp1(dir)=half*( &
            solzfab(D_DECL(i,j,k),partid_crit*SDIM+dir)+ &
            solzfab(D_DECL(i,j,k+1),partid_crit*SDIM+dir))
         endif

        else if (im_solid.eq.0) then ! in the fluid

         RCEN=xsten(0,1)

         if ((override_density.eq.0).or. & ! rho_t + div (rho u) = 0
             (override_density.eq.1)) then ! rho=rho(T,Y,z)
          DTEMP=zero
         else if (override_density.eq.2) then ! P_hydro=P_hydro(rho(T,Y,Z))
          im=1
          vofcomp=(im-1)*ngeom_recon+1
          FWATER=recon(D_DECL(i,j,k),vofcomp)
          if ((FWATER.le.half).and.(FWATER.ge.-VOFTOL)) then
           DTEMP=zero
          else if ((FWATER.ge.half).and.(FWATER.le.one+VOFTOL)) then

           if (num_materials_scalar_solve.eq.1) then
            liquid_temp=thermal(D_DECL(i,j,k),1)
           else if (num_materials_scalar_solve.eq.nmat) then
            liquid_temp=thermal(D_DECL(i,j,k),im)
           else
            print *,"num_materials_scalar_solve invalid"
            stop
           endif

           if (liquid_temp.le.zero) then
            print *,"liquid_temp cannot be <= 0 (1)"
            stop
           endif

           call thermal_offset(xsten,nhalf,temp_offset,gtemp_offset)
           liquid_temp=liquid_temp+temp_offset

           if (liquid_temp.le.zero) then
            print *,"liquid_temp cannot be <= 0 (2)"
            stop
           endif

           if (fort_drhodt(im).gt.zero) then
            print *,"fort_drhodt has invalid sign"
            stop
           endif
            ! units of drhodt are 1/(degrees Kelvin)
            ! DTEMP has no units
            ! fort_tempconst is the temperature of the inner boundary
            ! for the differentially heated rotating annulus problem.
           DTEMP=fort_drhodt(im)*(liquid_temp-fort_tempconst(im))
          else
           print *,"FWATER invalid"
           stop
          endif
         else
          print *,"override_density invalid"
          stop
         endif

          ! gravity force (temperature dependence)
          ! gravity_normalized>0 means that gravity is directed downwards.
          ! if invert_gravity==1, then gravity_normalized<0 (pointing upwards)
          ! units of gravity_normalized: m/s^2
          ! DTEMP has no units.
         unp1(grav_dir)=unp1(grav_dir)-dt*gravity_normalized*DTEMP

          ! polar coordinates: coriolis force (temperature dependence)
          !                    centrifugal force (temperature dependence).
          ! angular_velocity>0 => counter clockwise
          ! angular_velocity<0 => clockwise
          ! in PROB.F90: 
          ! pres=pres+half*rho*(angular_velocity**2)*(xpos(1)**2)
         if (rzflag.eq.3) then
          if (RCEN.le.zero) then
           print *,"RCEN invalid"
           stop
          endif
          unp1(1)=unp1(1)+dt*((un(2)**2)/RCEN+two*angular_velocity*un(2))
          unp1(2)=unp1(2)-dt*((un(1)*un(2))/RCEN+two*angular_velocity*un(1))

           ! DTEMP has no units.
          unp1(1)=unp1(1)+dt*DTEMP*(angular_velocity**2)*RCEN
         else if (rzflag.eq.0) then
          ! assume that RCEN > eps > 0 ?
          ! coriolis force:
          ! -2 omega cross v =
          !  i  j   k
          !  0  0   angular_velocity
          !  u  v   w
          ! = -2(-angular_vel. v,angular_velocity u)
          unp1(1)=unp1(1)+dt*( two*angular_velocity*un(2) )
          unp1(2)=unp1(2)-dt*( two*angular_velocity*un(1) )
         else if (rzflag.eq.1) then
          if (SDIM.ne.2) then
           print *,"dimension bust"
           stop
          endif
          if (angular_velocity.ne.zero) then
           print *,"angular_velocity<>0 not implemented here"
           stop
          endif
         else
          print *,"rzflag invalid"
          stop
         endif
            
         if (constant_viscosity.eq.0) then
          param1=three
          param2=two
         else if (constant_viscosity.eq.1) then
          param1=two
          param2=one
         else
          print *,"constant viscosity invalid"
          stop
         endif

         if (rzflag.eq.0) then
          ! do nothing
         else if (rzflag.eq.1) then
          if (SDIM.ne.2) then
           print *,"dimension bust"
           stop
          endif
         else if (rzflag.eq.3) then

          ut_comp=SDIM+1 ! u_t/r
          ut_over_r=tensor(D_DECL(i,j,k),ut_comp)
          vt_over_r=tensor(D_DECL(i,j,k),ut_comp+1)

           ! units of viscosity: kg/(m s)
           ! units of update:
           ! s kg/(m s) m^3/kg (m/s) (1/m^2)=m/s
          unp1(1)=unp1(1)-param1* &
            dt*visc_coef*mu_cell*inverseden*vt_over_r/RCEN
          unp1(2)=unp1(2)+param1* &
            dt*visc_coef*mu_cell*inverseden*ut_over_r/RCEN

         else
          print *,"rzflag invalid"
          stop
         endif
 
         if (rzflag.eq.0) then
          ! do nothing
         else if (rzflag.eq.1) then

          if (SDIM.ne.2) then
           print *,"dimension bust"
           stop
          endif
          if (RCEN.le.zero) then
           print *,"RCEN invalid"
           stop
          endif

           ! units of viscosity: kg/(m s)
           ! units of hoop_force_coef: s kg/(m s) m^3/kg (1/m^2)=1
          hoop_force_coef=dt*visc_coef*mu_cell*inverseden/(RCEN**2)
          if (hoop_force_coef.lt.zero) then
           print *,"hoop_force_coef invalid"
           stop
          endif

          if (update_state.eq.1) then
           unp1(1)=unp1(1)/(one+param2*hoop_force_coef)
          else if (update_state.eq.0) then
           unp1(1)=unp1(1)-param2*hoop_force_coef*un(1)
          else
           print *,"update_state invalid"
           stop
          endif

         else if (rzflag.eq.3) then

          if (RCEN.le.zero) then
           print *,"RCEN invalid"
           stop
          endif

          hoop_force_coef=dt*visc_coef*mu_cell*inverseden/(RCEN**2)
          if (hoop_force_coef.lt.zero) then
           print *,"hoop_force_coef invalid"
           stop
          endif

          if (update_state.eq.1) then
           unp1(1)=unp1(1)/(one+param2*hoop_force_coef)
           unp1(2)=unp1(2)/(one+hoop_force_coef)
          else if (update_state.eq.0) then
           unp1(1)=unp1(1)-param2*hoop_force_coef*un(1)
           unp1(2)=unp1(2)-hoop_force_coef*un(2)
          else
           print *,"update_state invalid"
           stop
          endif

         else
          print *,"rzflag invalid"
          stop
         endif

        else
         print *,"im_solid invalid 2"
         stop
        endif

        if (dt.le.zero) then
         print *,"dt invalid"
         stop
        endif

        ! viscosity force=-div(2 mu D)-HOOP_FORCE_MARK_MF
        do dir=1,SDIM
         force(D_DECL(i,j,k),dir)=(unp1(dir)-un(dir))/(inverseden*dt)
         if (update_state.eq.0) then
          ! do nothing
         else if (update_state.eq.1) then
          unew(D_DECL(i,j,k),dir)=unp1(dir)
         else
          print *,"update_state invalid"
          stop
         endif

        enddo ! dir=1..sdim

       enddo
       enddo
       enddo

       return
       end subroutine FORT_HOOPIMPLICIT


       subroutine FORT_COMPUTE_NEG_MOM_FORCE( &
         force,DIMS(force), &
         xlo,dx, &
         unew,DIMS(unew), &
         den,DIMS(den), &  ! 1/density
         tilelo,tilehi, &
         fablo,fabhi, &
         bfact, &
         level, &
         finest_level, &
         update_state, &
         dt, &
         prev_time, &
         cur_time, &
         nmat, &
         nsolveMM)

       use probf90_module
       use global_utility_module 

       IMPLICIT NONE

       INTEGER_T nmat
       INTEGER_T nsolveMM
       INTEGER_T level
       INTEGER_T finest_level
       INTEGER_T update_state
       REAL_T dt
       REAL_T prev_time,cur_time
       INTEGER_T tilelo(SDIM),tilehi(SDIM)
       INTEGER_T fablo(SDIM),fabhi(SDIM)
       INTEGER_T growlo(3),growhi(3)
       INTEGER_T bfact
    
       INTEGER_T DIMDEC(force)
       INTEGER_T DIMDEC(unew)
       INTEGER_T DIMDEC(den)

       REAL_T  force(DIMV(force),nsolveMM)
       REAL_T  unew(DIMV(unew),nsolveMM)
       REAL_T  den(DIMV(den),nmat+1)
       REAL_T  xlo(SDIM)
       REAL_T  xsten(-3:3,SDIM)
       REAL_T  dx(SDIM)

       INTEGER_T i,j,k,dir
       REAL_T inverseden
       INTEGER_T nhalf
       INTEGER_T nsolve
       REAL_T local_neg_force(SDIM)
       REAL_T xlocal(SDIM)

       nhalf=3

       if (num_materials_vel.ne.1) then
        print *,"num_materials_vel invalid"
        stop
       endif
       if ((num_materials_scalar_solve.ne.1).and. &
           (num_materials_scalar_solve.ne.nmat)) then
        print *,"num_materials_scalar_solve invalid"
        stop
       endif

       nsolve=SDIM
       if (nsolveMM.ne.nsolve*num_materials_vel) then
        print *,"nsolveMM invalid"
        stop
       endif
       if ((update_state.ne.0).and. &
           (update_state.ne.1)) then
        print *,"update_state invalid"
        stop
       endif
       if ((level.lt.0).or.(level.gt.finest_level)) then
        print *,"level invalid COMPUTE_NEG_MOM_FORCE"
        stop
       endif

       if (bfact.lt.1) then
        print *,"bfact invalid9"
        stop
       endif
       if (nmat.ne.num_materials) then
        print *,"nmat invalid"
        stop
       endif

       if (num_state_base.ne.2) then
        print *,"num_state_base invalid"
        stop
       endif

       if (update_state.eq.1) then
        if ((dt.le.zero).or. &
            (prev_time.lt.zero).or. &
            (abs(cur_time-prev_time-dt).gt.1.0E-4)) then
         print *,"dt, prev_time, or cur_time invalid (a)"
         stop
        endif
       else if (update_state.eq.0) then
        if ((dt.le.zero).or. &
            (prev_time.lt.zero).or. &
            (cur_time.lt.zero)) then
         print *,"dt, prev_time, or cur_time invalid (b)"
         stop
        endif
       else
        print *,"update_state invalid"
        stop
       endif

       call checkbound(fablo,fabhi,DIMS(force),1,-1,42)
       call checkbound(fablo,fabhi,DIMS(unew),1,-1,1330)
       call checkbound(fablo,fabhi,DIMS(den),1,-1,1330)

       call growntilebox(tilelo,tilehi,fablo,fabhi,growlo,growhi,0) 

       do i=growlo(1),growhi(1)
       do j=growlo(2),growhi(2)
       do k=growlo(3),growhi(3)

        call gridsten_level(xsten,i,j,k,level,nhalf)
        do dir=1,SDIM
         xlocal(dir)=xsten(0,dir)
        enddo

         ! force at time = cur_time
        call get_local_neg_mom_force(xlocal,prev_time,cur_time, &
          dt,update_state,local_neg_force)

        inverseden=den(D_DECL(i,j,k),1)
        if (inverseden.le.zero) then
         print *,"inverseden invalid"
         stop
        endif

        do dir=1,SDIM
         force(D_DECL(i,j,k),dir)=local_neg_force(dir)
         if (update_state.eq.0) then
          ! do nothing
         else if (update_state.eq.1) then
          unew(D_DECL(i,j,k),dir)=unew(D_DECL(i,j,k),dir)- &
           dt*local_neg_force(dir)*inverseden
         else
          print *,"update_state invalid"
          stop
         endif

        enddo ! dir=1..sdim

       enddo
       enddo
       enddo

       return
       end subroutine FORT_COMPUTE_NEG_MOM_FORCE


       subroutine FORT_THERMAL_OFFSET_FORCE( &
         override_density, &
         force,DIMS(force), &
         thermal,DIMS(thermal), &
         recon,DIMS(recon), &
         xlo,dx, &
         uold,DIMS(uold), &
         snew,DIMS(snew), &
         den,DIMS(den), &  ! 1/density
         DEDT,DIMS(DEDT), & ! 1/(rho cv)
         tilelo,tilehi, &
         fablo,fabhi, &
         bfact, &
         level, &
         finest_level, &
         update_state, &
         dt, &
         rzflag, &
         nmat, &
         nstate, &
         nsolveMM)

       use probf90_module
       use global_utility_module 

       IMPLICIT NONE

       INTEGER_T override_density
 
       INTEGER_T nmat
       INTEGER_T nstate
       INTEGER_T nsolveMM
       INTEGER_T level
       INTEGER_T finest_level
       INTEGER_T rzflag
       INTEGER_T update_state
       REAL_T dt
       INTEGER_T tilelo(SDIM),tilehi(SDIM)
       INTEGER_T fablo(SDIM),fabhi(SDIM)
       INTEGER_T growlo(3),growhi(3)
       INTEGER_T bfact
    
       INTEGER_T DIMDEC(force)
       INTEGER_T DIMDEC(thermal)
       INTEGER_T DIMDEC(recon)
       INTEGER_T DIMDEC(uold)
       INTEGER_T DIMDEC(snew)
       INTEGER_T DIMDEC(den)
       INTEGER_T DIMDEC(DEDT)

       REAL_T  force(DIMV(force),num_materials_scalar_solve)
       REAL_T  thermal(DIMV(thermal),num_materials_scalar_solve)
       REAL_T  recon(DIMV(recon),nmat*ngeom_recon)
       REAL_T  uold(DIMV(uold),nsolveMM)
       REAL_T  snew(DIMV(snew),nstate)
       REAL_T  den(DIMV(den),nmat+1)
       REAL_T  DEDT(DIMV(DEDT),nmat+1)
       REAL_T  xlo(SDIM)
       REAL_T  xsten(-3:3,SDIM)
       REAL_T  dx(SDIM)

       INTEGER_T i,j,k,dir
       REAL_T temp_n(num_materials_scalar_solve)
       REAL_T temp_np1(num_materials_scalar_solve)
       REAL_T DTEMP 
       REAL_T inverseden,over_rhocv
       INTEGER_T nhalf
       INTEGER_T im_temp
       INTEGER_T im_alt
       REAL_T temp_offset
       REAL_T gtemp_offset(SDIM)
       REAL_T dotprod
       INTEGER_T tempcomp

       nhalf=3

       if (num_materials_vel.ne.1) then
        print *,"num_materials_vel invalid"
        stop
       endif
       if ((num_materials_scalar_solve.ne.1).and. &
           (num_materials_scalar_solve.ne.nmat)) then
        print *,"num_materials_scalar_solve invalid"
        stop
       endif
       if (nsolveMM.ne.SDIM*num_materials_vel) then
        print *,"nsolveMM invalid"
        stop
       endif
       if (nstate.ne.num_materials_vel*(SDIM+1)+nmat*num_state_material+ &
           nmat*ngeom_raw+1) then
        print *,"nstate invalid"
        stop
       endif
       if ((update_state.ne.0).and. &
           (update_state.ne.1)) then
        print *,"update_state invalid"
        stop
       endif
       if ((level.lt.0).or.(level.gt.finest_level)) then
        print *,"level invalid thermal offset force"
        stop
       endif

       if (bfact.lt.1) then
        print *,"bfact invalid10"
        stop
       endif
       if (nmat.ne.num_materials) then
        print *,"nmat invalid"
        stop
       endif

       if (rzflag.eq.0) then
        ! do nothing
       else if (rzflag.eq.1) then
        if (SDIM.ne.2) then
         print *,"dimension bust"
         stop
        endif
       else if (rzflag.eq.3) then
        ! do nothing
       else 
        print *,"rzflag invalid"
        stop
       endif
       if (num_state_base.ne.2) then
        print *,"num_state_base invalid"
        stop
       endif

       call checkbound(fablo,fabhi,DIMS(force),1,-1,42)
       call checkbound(fablo,fabhi,DIMS(thermal),1,-1,1330)
       call checkbound(fablo,fabhi,DIMS(recon),1,-1,1330)
       call checkbound(fablo,fabhi,DIMS(uold),1,-1,1330)
       call checkbound(fablo,fabhi,DIMS(snew),1,-1,1330)
       call checkbound(fablo,fabhi,DIMS(den),1,-1,1330)
       call checkbound(fablo,fabhi,DIMS(DEDT),1,-1,1330)

       call growntilebox(tilelo,tilehi,fablo,fabhi,growlo,growhi,0) 

       do i=growlo(1),growhi(1)
       do j=growlo(2),growhi(2)
       do k=growlo(3),growhi(3)

        call gridsten_level(xsten,i,j,k,level,nhalf)

        do im_temp=1,num_materials_scalar_solve
         temp_n(im_temp)=thermal(D_DECL(i,j,k),im_temp)
         temp_np1(im_temp)=thermal(D_DECL(i,j,k),im_temp)
        enddo ! im_temp

        do im_temp=1,num_materials_scalar_solve

         if (num_materials_scalar_solve.eq.1) then
          inverseden=den(D_DECL(i,j,k),1)
          over_rhocv=DEDT(D_DECL(i,j,k),1)
         else if (num_materials_scalar_solve.eq.nmat) then
          inverseden=den(D_DECL(i,j,k),im_temp+1)
          over_rhocv=DEDT(D_DECL(i,j,k),im_temp+1)
         else
          print *,"num_materials_scalar_solve invalid"
          stop
         endif

         if (inverseden.le.zero) then
          print *,"inverseden invalid"
          stop
         endif
         if (over_rhocv.le.zero) then
          print *,"over_rhocv invalid"
          stop
         endif

         if ((override_density.eq.0).or. & ! Drho/DT=-divu rho
             (override_density.eq.1)) then ! rho=rho(T,Y,z)

          DTEMP=zero
          dotprod=zero

           ! P_hydro=P_hydro(rho(T,Y,Z)
           ! Boussinesq approximation.
           ! if gtemp_offset <> 0 then an extra term is added to 
           ! the temperature equation which comes from advection.
         else if (override_density.eq.2) then 
          call thermal_offset(xsten,nhalf,temp_offset,gtemp_offset)

          dotprod=zero

          do dir=1,SDIM
           dotprod=dotprod+uold(D_DECL(i,j,k),dir)*gtemp_offset(dir)
          enddo ! dir

          DTEMP=-dt*dotprod*over_rhocv
         else
          print *,"override_density invalid"
          stop
         endif

         ! thermal force=-div(k grad T)-THERMAL_FORCE_MF
         temp_np1(im_temp)=temp_np1(im_temp)+DTEMP 
         force(D_DECL(i,j,k),im_temp)=-dotprod

         if (update_state.eq.0) then
          ! do nothing
         else if (update_state.eq.1) then

          if (DTEMP.ne.zero) then

           tempcomp=num_materials_vel*(SDIM+1)+ &
            (im_temp-1)*num_state_material+2
           snew(D_DECL(i,j,k),tempcomp)=temp_np1(im_temp)

           if (num_materials_scalar_solve.eq.1) then
            do im_alt=2,nmat
             tempcomp=num_materials_vel*(SDIM+1)+ &
              (im_alt-1)*num_state_material+2
             snew(D_DECL(i,j,k),tempcomp)=temp_np1(im_temp)
            enddo
           else if (num_materials_scalar_solve.eq.nmat) then
            ! do nothing
           else
            print *,"num_materials_scalar_solve invalid"
            stop
           endif
 
          else if (DTEMP.eq.zero) then
    
           ! do nothing
 
          else
           print *,"DTEMP invalid"
           stop
          endif

         else
          print *,"update_state invalid"
          stop
         endif

        enddo ! im_temp= 1..num_materials_scalar_solve

       enddo
       enddo
       enddo

       return
       end subroutine FORT_THERMAL_OFFSET_FORCE



