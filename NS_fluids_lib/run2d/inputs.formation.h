# ------------------  INPUTS TO MAIN PROGRAM  -------------------
# CHANGES FROM PAST VERSION:
# no more raster stuff (hdf), add mac.mac_abs_tol
# blob.* now becomes ns.*
#
max_step  = 99999    # maximum timestep
#max_step  =  2    # maximum timestep
stop_time =  1000  # maximum problem time
thickness = 0.1

# ------------------  INPUTS TO CLASS AMR ---------------------
# set up for bubble
geometry.coord_sys      = 1        # 0 => cart, 1 => RZ
geometry.prob_lo   =  0.0 0.0
geometry.prob_hi   =  16.0 48.0

# multigrid class
#mg.verbose = 2
#cg.verbose = 2
# set above to 2 for maximum verbosity
mg.nu_f = 40
mg.nu_0 = 1   # 1 - v-cycle 2 - w-cycle
cg.maxiter = 200
mg.bot_atol = 1.0e-10
mg.rtol_b = -0.01
#Lp.v = 1
ns.be_cn_theta=0.5
ns.rk_theta=1.0

amr.n_cell    = 16 48
amr.max_level = 3
amr.max_level_front = 3
# 0- 1 level 1- 2 levels  2- 3 levels
amr.regrid_int      = 1       # how often to regrid
amr.n_error_buf     = 8 8 8 8 8    # number of buffer cells in error est
amr.grid_eff        = 0.45   # what constitutes an efficient grid
# above was .55 (smaller=> less boxes)
amr.blocking_factor = 8       # block factor in grid generation
amr.check_int       = 500      # number of timesteps between checkpoints
amr.check_file      = chk     # root name of checkpoint file
amr.plot_int        = 500
amr.plot_file       = plt 
amr.grid_log        = grdlog  # name of grid logging file
amr.max_grid_size   = 512
#amr.restart         = chk23500
#amr.trace   =1

# ------------------  INPUTS TO PHYSICS CLASS -------------------
ns.dt_cutoff      = 0.000005  # level 0 timestep below which we halt

proj.proj_tol       = 1.0e-8  # tolerence for projections
proj.sync_tol       = 1.0e-6   # tolerence for projections
proj.proj_abs_error = 1.0e-8  # abs error for proj multigrid iter
proj.bottom_tol     = 1.0e-10
proj.level_dump     = -1
mac.mac_tol        = 1.0e-8   # tolerence for mac projections
mac.mac_sync_tol   = 1.0e-6   # tolerence for mac SYNC projection
mac.mac_abs_tol    = 1.0e-8

ns.cfl            = 0.5      # cfl number for hyperbolic system
ns.init_shrink    = 1.0      # scale back initial timestep
ns.change_max     = 1.1      # scale back initial timestep
ns.visc_coef      = 0.0404 0.0404 0 0 0 0 0 0 0  # coef of viscosity
mac.visc_abs_tol   = 1.0e-6
ns.init_iter      = 2        # number of init iters to def pressure
ns.gravity        = -0.000928    # body force  (gravity in MKS units)
ns.gravityangle   = 0.0
ns.tension        = 0.00707    # interfacial tension force
#ns.fixed_dt	  = 0.0025     # hardwire dt
ns.sum_interval   = 1        # timesteps between computing mass 
proj.pres_interp    = 1
ns.do_sync_proj   = 1        # 1 => do Sync Project
ns.do_MLsync_proj = 0
ns.do_reflux      = 0        # 1 => do refluxing
ns.do_mac_proj    = 1        # 1 => do MAC projection
ns.usekluge       = 0
ns.RUNGAKUTTA = 0
ns.centerpressure=1
ns.visctimestep=1



ns.axis_dir=8
ns.vorterr=999999.0
ns.rgasinlet=1.57
ns.vinletgas=0.0
ns.twall=0.0
ns.advbot=0.0
ns.adv_vel=0.0
ns.adv_dir=1
ns.viscunburn=1.0
ns.viscburn=1.44444E-4
ns.tcenter=-1.0
ns.denspread=2.0
ns.denwater=1.0
ns.denair=0.000985
ns.xblob=0.0
ns.yblob=0.0
ns.zblob=1.0
ns.radblob=1.0
ns.denfact=1.0
ns.velfact=0.0
ns.probtype=25

proj.bogus_value = 5.0e+5
proj.Pcode = 0
#proj.Pcode = 2

#ns.mem_debug = 1
#ns.v = 1
#ns.d = 1

# ----------------  PROBLEM DEPENDENT INPUTS
ns.lo_bc          = 3 1 4
ns.hi_bc          = 4 2 4

# >>>>>>>>>>>>>  BC FLAGS <<<<<<<<<<<<<<<<
# 0 = Interior           3 = Symmetry
# 1 = Inflow             4 = SlipWall
# 2 = Outflow            5 = NoSlipWall

# turn any of these on to generate run-time timing stats


# select single or double precision of FAB output data
#        default is whatever precision code is compiled with.
#fab.precision = FLOAT     # output in FLOAT or DOUBLE
fab.precision = DOUBLE    # output in FLOAT or DOUBLE

# --------------------------------------------------------------------
# -----       CONTOUR PLOTTING ONLY AVAILABLE IN 2-D           -------
# --------------------------------------------------------------------
# uncomment the next line to set a default level for contour plotting
# contour.level = 1
#
# These variables control interactive contour plotting on UNIX systems
# file_name   = root name of postscript file (will be appended with ".ps")
# var_name    = name of thermodynamic variable to plot
# device      = 1  => XWINDOW, 2 = POSTSCRIPT, 3 = both
# freq        = intervals between plots (-1 = off)
# n_cont      = number of contour lines per plot
# sho_grd     = 0 => don't show grid placement, 1 => show grid placement
#               2 => show grid placement and overlay velocity vector plot
#               3 => same as 2 except show Up and not Ud
# win_siz     = number of pixels in max window direction
#
#file_name  var_name   device  freq  n_cont  sho_grd win_siz sval sdir sstr
contour.verbose = 1
contour.plot = triple triple  1   1    -1         2    600    -1   -1   0
contour.plot = triple triple  2 500    -1         2    800    -1   -1   0

