module react_util_module

  use amrex_fort_module, only : rt => amrex_real
  implicit none

contains

  subroutine single_zone_react_source(state, R, i, j, k, burn_state)

    use burn_type_module, only : burn_t, net_ienuc
    use network, only : nspec, nspec_evolve, aion
    use eos_module, only : eos
    use eos_type_module, only: eos_t, eos_input_re, eos_get_small_temp
    use meth_params_module, only : NVAR, URHO, UTEMP, UEDEN, UEINT, UMX, UMZ, UFS, UFX
    use amrex_constants_module, only : ZERO, HALF, ONE
    use actual_rhs_module
    use extern_probin_module, only : SMALL_X_SAFE, MAX_TEMP

    implicit none

    integer, intent(in) :: i, j, k
    real(rt), intent(in) :: state(NVAR)
    real(rt), intent(out) :: R(NVAR)
    type(burn_t), intent(inout) :: burn_state

    type(eos_t) :: eos_state
    real(rt) :: rhoInv, rho_e_K
    integer :: n
    real(rt) :: small_temp

    rhoInv = ONE / state(URHO)

    burn_state % rho = state(URHO)
    burn_state % T   = state(UTEMP)
    burn_state % e = state(UEINT) * rhoInv

    do n = 1, nspec
       burn_state % xn(n) = state(UFS+n-1) * rhoInv
    enddo

    burn_state % xn(1:nspec_evolve) = max(min(burn_state % xn(1:nspec_evolve), ONE), SMALL_X_SAFE) 

#if naux > 0
    do n = 1, naux
       burn_state % aux(n) = state(UFX+n-1) * rhoInv
    enddo
#endif

    ! Ensure that the temperature going in is consistent with the internal energy.
    call burn_to_eos(burn_state, eos_state)
    call eos(eos_input_re, eos_state)
    call eos_to_burn(eos_state, burn_state)

    call eos_get_small_temp(small_temp)
    burn_state % T = min(MAX_TEMP, max(burn_state % T, small_temp))

    burn_state % i = i
    burn_state % j = j
    burn_state % k = k

    burn_state % self_heat = .false.

    call actual_rhs(burn_state)

    ! store the instantaneous R
    R(:) = ZERO

    ! species rates come back in terms of molar fractions
    R(UFS:UFS-1+nspec_evolve) = &
         state(URHO) * aion(1:nspec_evolve) * burn_state % ydot(1:nspec_evolve)

    R(UEDEN) = state(URHO) * burn_state % ydot(net_ienuc)
    R(UEINT) = state(URHO) * burn_state % ydot(net_ienuc)

  end subroutine single_zone_react_source


  subroutine single_zone_jac(state, burn_state, dRdw)

    ! we assume that we are coming in with a valid burn_state, e.g., as called
    ! from single_zone_react_source

    use burn_type_module, only : burn_t, net_ienuc, net_itemp
    use network, only : nspec, nspec_evolve, aion, aion_inv
    use meth_params_module, only : NVAR, URHO, UTEMP, UEDEN, UEINT, UMX, UMZ, UFS, UFX
    use amrex_constants_module, only : ZERO, HALF, ONE
    use actual_rhs_module

    implicit none

    real(rt), intent(in) :: state(NVAR)
    type(burn_t), intent(inout) :: burn_state
    real(rt), intent(out) :: dRdw(0:nspec_evolve+1, 0:nspec_evolve+1)

    integer :: m, n
    type(burn_t) :: burn_state_pert

    ! for computing a numerical derivative
    real(rt) :: eps = 1.e-8_rt

    call actual_jac(burn_state)

    ! The Jacobian from the nets is in terms of dYdot/dY, but we want
    ! it was dXdot/dX, so convert here.
    do n = 1, nspec_evolve
       burn_state % jac(n,:) = burn_state % jac(n,:) * aion(n)
       burn_state % jac(:,n) = burn_state % jac(:,n) * aion_inv(n)
    enddo

    ! Our jacobian, dR/dw has the form:
    !
    !  /      0               0               0                    0       \
    !  | d(rho X1)/drho  d(rho X1)/dX1   d(rho X1)/dX2   ...  d(rho X1)/dT |
    !  | d(rho X1)/drho  d(rho X1)/dX1   d(rho X1)/dX2   ...  d(rho X1)/dT |
    !  |   ...                                                             |
    !  \ d(rho E)/drho   d(rho E)/dX1    d(rho E)/dX2    ...  d(rho E)/dT  /

    dRdw(:,:) = ZERO

    ! now perturb density and call the RHS to compute the derivative wrt rho
    ! species rates come back in terms of molar fractions
    call copy_burn_t(burn_state_pert, burn_state)
    burn_state_pert % rho = burn_state % rho * (ONE + eps)

    burn_state_pert % i = burn_state % i
    burn_state_pert % j = burn_state % j
    burn_state_pert % k = burn_state % k

    call actual_rhs(burn_state_pert)

    ! fill the column of dRdw corresponding to the derivative
    ! with respect to rho
    do m = 1, nspec_evolve
       ! d( d(rho X_m)/dt)/drho
       dRdw(m, 0) = burn_state % ydot(m) + &
            state(URHO) * (burn_state_pert % ydot(m) - burn_state % ydot(m))/(eps * burn_state % rho)
    enddo

    ! d( d(rho E)/dt)/drho
    dRdw(nspec_evolve+1, 0) = burn_state % ydot(net_ienuc) + &
         state(URHO) * (burn_state_pert % ydot(net_ienuc) - burn_state % ydot(net_ienuc))/(eps * burn_state % rho)

    ! fill the columns of dRdw corresponding to each derivative
    ! with respect to species mass fraction
    do n = 1, nspec_evolve
       dRdw(0, n) = ZERO  ! density source

       do m = 1, nspec_evolve
          ! d( d(rho X_m)/dt)/dX_n
          dRdw(m, n) = state(URHO) * aion(m) * burn_state % jac(m, n)
       enddo

       ! d( d(rho E)/dt)/dX_n
       dRdw(nspec_evolve+1, n) = state(URHO) * burn_state % jac(net_ienuc, n)

    enddo

    ! now fill the column corresponding to derivatives with respect to
    ! temperature -- this column is nspec_evolve+1
    dRdw(0, nspec_evolve+1) = ZERO

    ! d( d(rho X_m)/dt)/dT
    do m = 1, nspec_evolve
       dRdw(m, nspec_evolve+1) = state(URHO) * burn_state % jac(m, net_itemp)
    enddo

    ! d( d(rho E)/dt)/dT
    dRdw(nspec_evolve+1, nspec_evolve+1) = state(URHO) * burn_state % jac(net_ienuc, net_itemp)


  end subroutine single_zone_jac

end module react_util_module
