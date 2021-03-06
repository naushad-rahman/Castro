subroutine amrex_probinit (init,name,namlen,problo,probhi) bind(c)

  use amrex_constants_module, only: ZERO, HALF, ONE
  use probdata_module, only: rho0, drho0, xn_zone
  use prob_params_module, only: center
  use amrex_error_module, only: amrex_error
  use amrex_fort_module, only: rt => amrex_real

  implicit none

  integer,  intent(in) :: init, namlen
  integer,  intent(in) :: name(namlen)
  real(rt), intent(in) :: problo(3), probhi(3)

  integer :: untin, i

  namelist /fortin/ rho0, drho0

  ! Build "probin" filename -- the name of file containing fortin namelist.
  integer, parameter :: maxlen = 256
  character :: probin*(maxlen)

  if (namlen .gt. maxlen) then
     call amrex_error('probin file name too long')
  end if

  do i = 1, namlen
     probin(i:i) = char(name(i))
  end do

  ! Set namelist defaults

  rho0 = 1.4_rt
  drho0 = 0.14_rt

  ! Read namelists
  open(newunit=untin, file=probin(1:namlen), form='formatted', status='old')
  read(untin, fortin)
  close(unit=untin)

  ! set explosion center
  center(:) = HALF * (problo(:) + probhi(:))

  xn_zone(:) = ZERO
  xn_zone(1) = ONE

end subroutine amrex_probinit


subroutine ca_initdata(level, time, lo, hi, nscal, &
                       state, s_lo, s_hi, &
                       dx, xlo, xhi)

  use probdata_module, only: rho0, drho0, xn_zone
  use amrex_constants_module, only: M_PI, FOUR3RD, ZERO, HALF, ONE
  use meth_params_module , only: NVAR, URHO, UMX, UMZ, UEDEN, UEINT, UFS
  use prob_params_module, only: center, coord_type
  use amrex_fort_module, only: rt => amrex_real
  use network, only: nspec
  use extern_probin_module, only: eos_gamma

  implicit none

  integer,  intent(in   ) :: level, nscal
  integer,  intent(in   ) :: lo(3), hi(3)
  integer,  intent(in   ) :: s_lo(3), s_hi(3)
  real(rt), intent(in   ) :: xlo(3), xhi(3), time, dx(3)
  real(rt), intent(inout) :: state(s_lo(1):s_hi(1), s_lo(2):s_hi(2), s_lo(3):s_hi(3), NVAR)

  real(rt) :: xx, yy, zz
  real(rt) :: dist, p, eint
  integer  :: i, j, k

  do k = lo(3), hi(3)
     zz = xlo(3) + dx(3) * (dble(k - lo(3)) + HALF)
     do j = lo(2), hi(2)
        yy = xlo(2) + dx(2) * (dble(j - lo(2)) + HALF)
        do i = lo(1), hi(1)
           xx = xlo(1) + dx(1) * (dble(i - lo(1)) + HALF)

           dist = sqrt((center(1)-xx)**2 + (center(2)-yy)**2 + (center(3)-zz)**2)

           if (dist <= HALF) then
              state(i,j,k,URHO) = rho0 + drho0 * exp(-16.d0*dist**2) * cos(M_PI*dist)**6
           else
              state(i,j,k,URHO) = rho0
           endif

           state(i,j,k,UMX:UMZ) = 0.e0_rt

           ! we are isentropic, so p = (dens/rho0)**Gamma_1
           p = (state(i,j,k,URHO)/rho0)**eos_gamma
           eint = p / (eos_gamma - ONE)

           state(i,j,k,UEDEN) = eint
           state(i,j,k,UEINT) = eint

           state(i,j,k,UFS:UFS-1+nspec) = state(i,j,k,URHO) * xn_zone(:)

        end do
     end do
  end do

end subroutine ca_initdata
