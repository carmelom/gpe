module io
  ! Routines for input/output
  use parameters
  implicit none

  private
  public :: open_files, close_files, save_time, save_energy, &
            save_surface, idl_surface, end_state, get_zeros, get_re_im_zeros, &
            get_extra_zeros, save_linelength, save_momentum, &
            get_dirs, diag, condensed_particles

  contains

  function itos(n)
    ! Convert an integer into a string of length 7
    implicit none

    integer, intent(in) :: n 
    integer             :: i, n_, d(7)
    character(7)        :: itos
    character           :: c(0:9) = (/'0','1','2','3','4','5',&
                                      '6','7','8','9'/)

    n_ = n
    do i = 7, 1, -1
      d(i) = mod(n_,10)
      n_ = n_ / 10
    end do

    itos = c(d(1))//c(d(2))//c(d(3))//c(d(4))//c(d(5))//c(d(6))//c(d(7))

    return
  end function itos

  subroutine open_files()
    ! Open runtime files
    implicit none

    if (myrank == 0) then
      open (10, file='u_time.dat', status='unknown')
      open (11, file='timestep.dat', status='unknown')
      open (12, file='energy.dat', status='unknown')
      open (13, file='linelength.dat', status='unknown')
      open (14, file='momentum.dat', status='unknown')
      open (15, file='mass.dat', status='unknown')
      open (99, file='RUNNING')
      close (99)
    end if

    return
  end subroutine open_files

  subroutine close_files()
    ! Close runtime files
    implicit none

    if (myrank == 0) then
      close (10)
      close (11)
      close (12)
      close (13)
      close (14)
      close (15)
    end if

    return
  end subroutine close_files

  subroutine get_dirs()
    ! Get named directories where each process can write its own data
    use parameters
    implicit none

    ! Directory names are proc** with ** replaced by the rank of each process
    if (myrank < 10) then
      write (proc_dir(6:6), '(1i1)') myrank
      write (proc_dir(5:5), '(1i1)') 0
    else
      write (proc_dir(5:6), '(1i2)') myrank
    end if

    return
  end subroutine get_dirs

  subroutine save_time(time, in_var)
    ! Save time-series data
    use parameters
    use variables, only : get_phase, get_density
    implicit none

    real, intent(in) :: time
    complex, dimension(0:nx1,jsta:jend,ksta:kend), intent(in) :: in_var
    real, dimension(0:nx1,jsta:jend,ksta:kend) :: phase, density
    complex, dimension(3) :: tmp, var
    real :: xpos, ypos, zpos
    integer :: i, j, k

    call get_phase(in_var, phase)
    call get_density(in_var, density)

    xpos = nx/2
    ypos = ny/2
    zpos = nz/2

    tmp = 0.0
    ! Find out on which process the data occurs and copy it into a temporary
    ! array
    do k=ksta,kend
      do j=jsta,jend
        do i=0,nx1
          if ((i==xpos) .and. (j==ypos) .and. (k==zpos)) then
            tmp(1) = in_var(xpos,ypos,zpos)
            tmp(2) = density(xpos,ypos,zpos)
            tmp(3) = phase(xpos,ypos,zpos)
          end if
        end do
      end do
    end do

    ! Make sure process 0 has the correct data to write
    call MPI_REDUCE(tmp, var, 3, MPI_COMPLEX, MPI_SUM, 0, &
                    MPI_COMM_WORLD, ierr)

    ! Write the data to file
    if (myrank == 0) then
      write (10, '(6e17.9)') time, im_t, real(var(1)), &
                             aimag(var(1)), real(var(2)), real(var(3))
    end if

    return
  end subroutine save_time

  subroutine save_energy(time, in_var)
    ! Save the energy
    use parameters
    use variables, only : energy
    implicit none

    real, intent(in) :: time
    complex, dimension(0:nx1,jsta-2:jsta+2,ksta-2:kend+2), intent(in) :: in_var
    real :: E

    call energy(in_var, E)
    
    if (myrank == 0) then
      write (12, '(2e17.9)') time, E
    end if

    return
  end subroutine save_energy
  
  subroutine condensed_particles(time, in_var)
    ! Save the mass
    use parameters
    use ic, only : fft
    use variables, only : mass, unit_no
    implicit none

    real, intent(in) :: time
    complex, dimension(0:nx1,jsta:jend,ksta:kend), intent(in) :: in_var
    complex, dimension(0:nx1,jsta:jend,ksta:kend) :: a
    real :: M, n0, temp, tot, tmp, rho0
    integer :: i, j, k, k2, k4

    call fft(in_var, a, 'backward', .true.)
    
    !call fft(a, in_var, 'forward', .true.)
    !open (unit_no, status='unknown', file=proc_dir//'fft'//itos(p)//'.dat', &
    !      form='unformatted')
    !
    !write (unit_no) nx, ny, nz
    !write (unit_no) nyprocs, nzprocs
    !write (unit_no) jsta, jend, ksta, kend
    !write (unit_no) abs(in_var)
    !write (unit_no) x
    !write (unit_no) y
    !write (unit_no) z

    !close (unit_no)

    !call MPI_BARRIER(MPI_COMM_WORLD, ierr)
    !stop
    
    do k=ksta,kend
      do j=jsta,jend
        if ((j==0) .and. (k==0)) then
          n0 = abs(a(0,0,0))**2
          exit
        end if
      end do
    end do
    call mass(in_var, M)
    
    call MPI_BCAST(n0, 1, MPI_REAL, 0, MPI_COMM_WORLD, ierr)

    tmp = 0.0
    rho0 = n0/(nx*ny*nz)
    
    do k=ksta,kend
      do j=jsta,jend
        do i=0,nx1
          if (i==0 .and. j==0 .and. k==0) cycle
          k2 = i**2 + j**2 + k**2
          k4 = k2**2
          tmp = tmp + (k2+rho0)/(k4+2.0*rho0*k2)
        end do
      end do
    end do
    
    call MPI_REDUCE(tmp, tot, 1, MPI_REAL, MPI_SUM, 0, &
                    MPI_COMM_WORLD, ierr)

    if (myrank == 0) then
      temp = (M-n0)/tot
      write (15, '(4e17.9)') time, M/(8.0*xr*yr*zr), n0/(nx*ny*nz), temp
    end if

    
    do k=ksta,kend
      do j=jsta,jend
        if (j/=k) cycle
        do i=0,nx1
          if (i/=j) cycle
          open (unit_no, position='append', &
                         file=proc_dir//'spectrum'//itos(p)//'.dat')
          write (unit_no, '(3i5,e17.9)') i, j, k, abs(a(i,j,k))**2
          close (unit_no)
        end do
      end do
    end do
    
    return
  end subroutine condensed_particles
  
  subroutine save_momentum(time, in_var)
    ! Save the momentum
    use parameters
    use variables, only : momentum
    implicit none

    real, intent(in) :: time
    complex, dimension(0:nx1,jsta-2:jend+2,ksta-2:kend+2), intent(in) :: in_var
    real, dimension(3) :: P

    call momentum(in_var, P)
    
    if (myrank == 0) then
      write (14, '(4e17.9)') time, P(1), P(2), P(3)
    end if

    return
  end subroutine save_momentum

  subroutine save_surface(p, in_var)
    ! Save 2D surface data for use in gnuplot.  The data is saved separately on
    ! each process so a shell script must be used to plot it
    use parameters
    use variables
    use ic, only : x, y, z
    implicit none

    integer, intent(in) :: p
    complex, dimension(0:nx1,jsta:jend,ksta:kend), intent(in) :: in_var
    real, dimension(0:nx1,jsta:jend,ksta:kend) :: phase, density
    real :: zpos
    integer :: i, j, k

    ! Get the phase and the density
    call get_phase(in_var, phase)
    call get_density(in_var, density)
    
    zpos = nz/2

    ! Write each process's own data to file, but only if 'zpos' resides on that
    ! particular process
    do k=ksta,kend
      if (k==zpos) then
        open (unit_no, status='unknown', file=proc_dir//'u'//itos(p)//'.dat')
        do i=0,nx1
          write (unit_no, '(6e17.9)') (x(i), y(j), density(i,j,zpos), &
                                  phase(i,j,zpos), real(in_var(i,j,zpos)), &
                                  aimag(in_var(i,j,zpos)), j=jsta,jend)
          write (unit_no, *)
        end do
        close (unit_no)
        exit
      end if
    end do
    
    return
  end subroutine save_surface
  
  subroutine idl_surface(p, in_var)
    ! Save 3D isosurface data for use in IDL.  As for the gnuplot plots, this
    ! data is saved separately for each process.  It must be read in through
    ! IDL
    use parameters
    use variables, only : unit_no
    use ic, only : x, y, z
    implicit none

    integer, intent(in) :: p
    complex, intent(in) :: in_var(0:nx1,jsta:jend,ksta:kend)
    integer :: i, j, k

    open (unit_no, status='unknown', file=proc_dir//'u_idl'//itos(p)//'.dat', &
          form='unformatted')
    
    write (unit_no) nx, ny, nz
    write (unit_no) nyprocs, nzprocs
    write (unit_no) jsta, jend, ksta, kend
    write (unit_no) abs(in_var)**2
    write (unit_no) x
    write (unit_no) y
    write (unit_no) z

    close (unit_no)

    return
  end subroutine idl_surface

  subroutine end_state(in_var, p, flag)
    ! Save variables for use in a restarted run.  Each process saves its own
    ! bit
    use parameters
    use variables, only : unit_no
    implicit none

    integer, intent(in) :: p, flag
    complex, dimension(0:nx1,jsta:jend,ksta:kend), intent(in) :: in_var
    integer :: j, k

    open (unit_no, file=proc_dir//'end_state.dat', form='unformatted')

    write (unit_no) nx
    write (unit_no) ny
    write (unit_no) nz
    write (unit_no) p
    write (unit_no) t
    write (unit_no) dt
    write (unit_no) in_var

    close (unit_no)

    ! Write the variables at the last save
    if (myrank == 0) then
      open (98, file = 'save.dat')
      write (98, *) 'Periodically saved state'
      write (98, *) 't=', t
      write (98, *) 'dt=', dt
      write (98, *) 'nx=', nx
      write (98, *) 'ny=', ny
      write (98, *) 'nz=', nz
      write (98, *) 'p=', p
      close (98)
    end if
    
    if (myrank == 0) then
      ! flag = 1 if the run has been ended
      if (flag == 1) then
        ! Delete RUNNING file to cleanly terminate the run
        open (99, file = 'RUNNING')
        close (99, status = 'delete')
      end if
    end if

    return
  end subroutine end_state
  
  subroutine get_zeros(in_var, p)
    ! Find all the zeros of the wavefunction by determining where the real and
    ! imaginary parts simultaneously go to zero.  This routine doesn't find
    ! them all though - get_extra_zeros below finds the rest
    
    ! All the zeros routines are horrible - I'm sure there is a more efficient
    ! way of calculating them
    use parameters
    use variables, only : re_im, unit_no
    use ic, only : x, y, z
    implicit none

    complex, dimension(0:nx1,jsta-2:jend+2,ksta-2:kend+2), intent(in) :: in_var
    integer, intent(in) :: p
    type (re_im) :: var
    real :: zero
    real, dimension(0:nx1,jsta:jend,ksta:kend) :: denom
    integer :: i, j, k
    !integer, parameter :: z_start=nz/2, z_end=nz/2
    integer :: z_start, z_end

    ! Decide whether to find the zeros over the whole 3D box or just over a 2D
    ! plane
    z_start=ksta
    z_end=kend

    allocate(var%re(0:nx1,jsta-2:jend+2,ksta-2:kend+2))
    allocate(var%im(0:nx1,jsta-2:jend+2,ksta-2:kend+2))
    
    open (unit_no, status='unknown', file=proc_dir//'zeros'//itos(p)//'.dat')
    
    var%re = real(in_var)
    var%im = aimag(in_var)

    write (unit_no, *) "# i,j,k --> i+1,j,k"

    !do k=nz/2+0, nz/2+0
    do k=z_start,z_end
      if ((k==0) .or. (k==nz1)) cycle
      do j=jsta,jend
        if ((j==0) .or. (j==ny1)) cycle
        do i=1,nx1-1
          if (((var%re(i,j,k) == 0.0) .and. &
               (var%im(i,j,k) == 0.0)) .or. &
              ((var%re(i,j,k) == 0.0) .and. &
               (var%im(i,j,k)*var%im(i+1,j,k) < 0.0)) .or. &
              ((var%im(i,j,k) == 0.0) .and. &
               (var%re(i,j,k)*var%re(i+1,j,k) < 0.0)) .or. &
              ((var%re(i,j,k)*var%re(i+1,j,k) < 0.0) .and. &
               (var%im(i,j,k)*var%im(i+1,j,k) < 0.0)) ) then
            denom(i,j,k) = var%re(i,j,k)-var%re(i+1,j,k)
            if (denom(i,j,k) == 0.0) cycle
            zero = -var%re(i+1,j,k)*x(i)/denom(i,j,k) + &
                    var%re(i,j,k)*x(i+1)/denom(i,j,k)
            write (unit_no, '(3e17.9)') zero, y(j), z(k)
          end if
        end do
      end do
    end do
    
    write (unit_no, *) "# i,j,k --> i,j+1,k"

    do k=z_start,z_end
      if ((k==0) .or. (k==nz1)) cycle
      do j=jsta,jend
        if ((j==0) .or. (j==ny1)) cycle
        do i=1,nx1-1
          if (((var%re(i,j,k) == 0.0) .and. &
               (var%im(i,j,k) == 0.0)) .or. &
              ((var%re(i,j,k) == 0.0) .and. &
               (var%im(i,j,k)*var%im(i,j+1,k) < 0.0)) .or. &
              ((var%im(i,j,k) == 0.0) .and. &
               (var%re(i,j,k)*var%re(i,j+1,k) < 0.0)) .or. &
              ((var%re(i,j,k)*var%re(i,j+1,k) < 0.0) .and. &
               (var%im(i,j,k)*var%im(i,j+1,k) < 0.0)) ) then
            denom(i,j,k) = var%re(i,j,k)-var%re(i,j+1,k)
            if (denom(i,j,k) == 0.0) cycle
            zero = -var%re(i,j+1,k)*y(j)/denom(i,j,k) + &
                    var%re(i,j,k)*y(j+1)/denom(i,j,k)
            write (unit_no, '(3e17.9)') x(i), zero, z(k)
          end if
        end do
      end do
    end do
    
    if (z_start /= z_end) then
      write (unit_no, *) "# i,j,k --> i,j,k+1"

      do k=z_start,z_end
        if ((k==0) .or. (k==nz1)) cycle
        do j=jsta,jend
          if ((j==0) .or. (j==ny1)) cycle
          do i=1,nx1-1
            if (((var%re(i,j,k) == 0.0) .and. &
                 (var%im(i,j,k) == 0.0)) .or. &
                ((var%re(i,j,k) == 0.0) .and. &
                 (var%im(i,j,k)*var%im(i,j,k+1) < 0.0)) .or. &
                ((var%im(i,j,k) == 0.0) .and. &
                 (var%re(i,j,k)*var%re(i,j,k+1) < 0.0)) .or. &
                ((var%re(i,j,k)*var%re(i,j,k+1) < 0.0) .and. &
                 (var%im(i,j,k)*var%im(i,j,k+1) < 0.0)) ) then
              denom(i,j,k) = var%re(i,j,k)-var%re(i,j,k+1)
              if (denom(i,j,k) == 0.0) cycle
              zero = -var%re(i,j,k+1)*z(k)/denom(i,j,k) + &
                      var%re(i,j,k)*z(k+1)/denom(i,j,k)
              write (unit_no, '(3e17.9)') x(i), y(j), zero
            end if
          end do
        end do
      end do
    end if

    close (unit_no)

    deallocate(var%re)
    deallocate(var%im)

    return
  end subroutine get_zeros

  subroutine get_extra_zeros(in_var, p)
    ! Find the zeros that the get_zeros routine did not pick up
    use parameters
    use variables, only : re_im, unit_no
    use ic, only : x, y, z
    implicit none

    complex, dimension(0:nx1,jsta-2:jend+2,ksta-2:kend+2), intent(in) :: in_var
    integer, intent(in) :: p
    type (re_im) :: var
    real, dimension(4) :: zero
    real, dimension(2) :: m
    real, dimension(4,0:nx1,jsta:jend,ksta:kend) :: denom
    real :: xp, yp, zp
    integer :: i, j, k
    !integer, parameter :: z_start=nz/2, z_end=nz/2
    integer :: z_start, z_end

    z_start=ksta
    z_end=kend

    allocate(var%re(0:nx1,jsta-2:jend+2,ksta-2:kend+2))
    allocate(var%im(0:nx1,jsta-2:jend+2,ksta-2:kend+2))

    ! Write these new zeros to the same file as for the get_zeros routine
    open (unit_no, status='old', position='append', &
                   file=proc_dir//'zeros'//itos(p)//'.dat')

    var%re = real(in_var)
    var%im = aimag(in_var)
    
    write (unit_no, *) "# i,j,k --> i+1,j,k --> i+1,j+1,k --> i,j+1,k"
    
    do k=z_start,z_end
      if ((k==0) .or. (k==nz1)) cycle
      do j=jsta,jend
        if ((j==0) .or. (j==ny1)) cycle
        do i=1,nx1-1
          if (((var%re(i,j,k)*var%re(i+1,j,k) < 0.0) .and. &
               (var%im(i,j,k)*var%im(i+1,j,k) >= 0.0)) .and. &
              ((var%im(i+1,j,k)*var%im(i+1,j+1,k) < 0.0) .and. &
               (var%re(i+1,j,k)*var%re(i+1,j+1,k) >= 0.0)) .and. &
              ((var%re(i+1,j+1,k)*var%re(i,j+1,k) < 0.0) .and. &
               (var%im(i+1,j+1,k)*var%im(i,j+1,k) >= 0.0)) .and. &
              ((var%im(i,j+1,k)*var%im(i,j,k) < 0.0) .and. &
               (var%re(i,j+1,k)*var%re(i,j,k) >= 0.0)) ) then
            denom(1,i,j,k) = var%re(i,j,k)-var%re(i+1,j,k)
            zero(1) = -var%re(i+1,j,k)*x(i)/denom(1,i,j,k) + &
                       var%re(i,j,k)*x(i+1)/denom(1,i,j,k)
            denom(2,i,j,k) = var%im(i+1,j,k)-var%im(i+1,j+1,k)
            zero(2) = -var%im(i+1,j+1,k)*y(j)/denom(2,i,j,k) + &
                       var%im(i+1,j,k)*y(j+1)/denom(2,i,j,k)
            denom(3,i,j,k) = var%re(i+1,j+1,k)-var%re(i,j+1,k)
            zero(3) = -var%re(i,j+1,k)*x(i+1)/denom(3,i,j,k) + &
                       var%re(i+1,j+1,k)*x(i)/denom(3,i,j,k)
            denom(4,i,j,k) = var%im(i,j+1,k)-var%im(i,j,k)
            zero(4) = -var%im(i,j,k)*y(j+1)/denom(4,i,j,k) + &
                       var%im(i,j+1,k)*y(j)/denom(4,i,j,k)
            m(1) = (y(j)-y(j+1))/(zero(1)-zero(3))
            m(2) = (zero(2)-zero(4))/(x(i+1)-x(i))
            xp = (zero(4)-x(i)*m(2)-y(j)+zero(1)*m(1))/(m(1)-m(2))
            yp = xp*m(1)+y(j)-zero(1)*m(1)
            
            write (unit_no, '(3e17.9)') xp, yp, z(k)
          else if (((var%im(i,j,k)*var%im(i+1,j,k) < 0.0) .and. &
                    (var%re(i,j,k)*var%re(i+1,j,k) >= 0.0)) .and. &
                   ((var%re(i+1,j,k)*var%re(i+1,j+1,k) < 0.0) .and. &
                    (var%im(i+1,j,k)*var%im(i+1,j+1,k) >= 0.0)) .and. &
                   ((var%im(i+1,j+1,k)*var%im(i,j+1,k) < 0.0) .and. &
                    (var%re(i+1,j+1,k)*var%re(i,j+1,k) >= 0.0)) .and. &
                   ((var%re(i,j+1,k)*var%re(i,j,k) < 0.0) .and. &
                    (var%im(i,j+1,k)*var%im(i,j,k) >= 0.0)) ) then
            denom(1,i,j,k) = var%im(i,j,k)-var%im(i+1,j,k)
            zero(1) = -var%im(i+1,j,k)*x(i)/denom(1,i,j,k) + &
                       var%im(i,j,k)*x(i+1)/denom(1,i,j,k)
            denom(2,i,j,k) = var%re(i+1,j,k)-var%re(i+1,j+1,k)
            zero(2) = -var%re(i+1,j+1,k)*y(j)/denom(2,i,j,k) + &
                       var%re(i+1,j,k)*y(j+1)/denom(2,i,j,k)
            denom(3,i,j,k) = var%im(i+1,j+1,k)-var%im(i,j+1,k)
            zero(3) = -var%im(i,j+1,k)*x(i+1)/denom(3,i,j,k) + &
                       var%im(i+1,j+1,k)*x(i)/denom(3,i,j,k)
            denom(4,i,j,k) = var%re(i,j+1,k)-var%re(i,j,k)
            zero(4) = -var%re(i,j,k)*y(j+1)/denom(4,i,j,k) + &
                       var%re(i,j+1,k)*y(j)/denom(4,i,j,k)
            m(1) = (y(j)-y(j+1))/(zero(1)-zero(3))
            m(2) = (zero(2)-zero(4))/(x(i+1)-x(i))
            xp = (zero(4)-x(i)*m(2)-y(j)+zero(1)*m(1))/(m(1)-m(2))
            yp = xp*m(1)+y(j)-zero(1)*m(1)

            write (unit_no, '(3e17.9)') xp, yp, z(k)
          end if
        end do
      end do
    end do
    
    if (z_start /= z_end) then
      write (unit_no, *) "# i,j,k --> i+1,j,k --> i+1,j,k+1 --> i,j,k+1"
      do k=z_start,z_end
        if ((k==0) .or. (k==nz1)) cycle
        do j=jsta,jend
          if ((j==0) .or. (j==ny1)) cycle
          do i=1,nx1-1
            if (((var%re(i,j,k)*var%re(i+1,j,k) < 0.0) .and. &
                 (var%im(i,j,k)*var%im(i+1,j,k) >= 0.0)) .and. &
                ((var%im(i+1,j,k)*var%im(i+1,j,k+1) < 0.0) .and. &
                 (var%re(i+1,j,k)*var%re(i+1,j,k+1) >= 0.0)) .and. &
                ((var%re(i+1,j,k+1)*var%re(i,j,k+1) < 0.0) .and. &
                 (var%im(i+1,j,k+1)*var%im(i,j,k+1) >= 0.0)) .and. &
                ((var%im(i,j,k+1)*var%im(i,j,k) < 0.0) .and. &
                 (var%re(i,j,k+1)*var%re(i,j,k) >= 0.0)) ) then
              denom(1,i,j,k) = var%re(i,j,k)-var%re(i+1,j,k)
              zero(1) = -var%re(i+1,j,k)*x(i)/denom(1,i,j,k) + &
                         var%re(i,j,k)*x(i+1)/denom(1,i,j,k)
              denom(2,i,j,k) = var%im(i+1,j,k)-var%im(i+1,j,k+1)
              zero(2) = -var%im(i+1,j,k+1)*z(k)/denom(2,i,j,k) + &
                         var%im(i+1,j,k)*z(k+1)/denom(2,i,j,k)
              denom(3,i,j,k) = var%re(i+1,j,k+1)-var%re(i,j,k+1)
              zero(3) = -var%re(i,j,k+1)*x(i+1)/denom(3,i,j,k) + &
                         var%re(i+1,j,k+1)*x(i)/denom(3,i,j,k)
              denom(4,i,j,k) = var%im(i,j,k+1)-var%im(i,j,k)
              zero(4) = -var%im(i,j,k)*z(k+1)/denom(4,i,j,k) + &
                         var%im(i,j,k+1)*z(k)/denom(4,i,j,k)
              m(1) = (z(k)-z(k+1))/(zero(1)-zero(3))
              m(2) = (zero(2)-zero(4))/(x(i+1)-x(i))
              xp = (zero(4)-x(i)*m(2)-z(k)+zero(1)*m(1))/(m(1)-m(2))
              zp = xp*m(1)+z(k)-zero(1)*m(1)
              
              write (unit_no, '(3e17.9)') xp, y(j), zp
            else if (((var%im(i,j,k)*var%im(i+1,j,k) < 0.0) .and. &
                      (var%re(i,j,k)*var%re(i+1,j,k) >= 0.0)) .and. &
                     ((var%re(i+1,j,k)*var%re(i+1,j,k+1) < 0.0) .and. &
                      (var%im(i+1,j,k)*var%im(i+1,j,k+1) >= 0.0)) .and. &
                     ((var%im(i+1,j,k+1)*var%im(i,j,k+1) < 0.0) .and. &
                      (var%re(i+1,j,k+1)*var%re(i,j,k+1) >= 0.0)) .and. &
                     ((var%re(i,j,k+1)*var%re(i,j,k) < 0.0) .and. &
                      (var%im(i,j,k+1)*var%im(i,j,k) >= 0.0)) ) then
              denom(1,i,j,k) = var%im(i,j,k)-var%im(i+1,j,k)
              zero(1) = -var%im(i+1,j,k)*x(i)/denom(1,i,j,k) + &
                         var%im(i,j,k)*x(i+1)/denom(1,i,j,k)
              denom(2,i,j,k) = var%re(i+1,j,k)-var%re(i+1,j,k+1)
              zero(2) = -var%re(i+1,j,k+1)*z(k)/denom(2,i,j,k) + &
                         var%re(i+1,j,k)*z(k+1)/denom(2,i,j,k)
              denom(3,i,j,k) = var%im(i+1,j,k+1)-var%im(i,j,k+1)
              zero(3) = -var%im(i,j,k+1)*x(i+1)/denom(3,i,j,k) + &
                         var%im(i+1,j,k+1)*x(i)/denom(3,i,j,k)
              denom(4,i,j,k) = var%re(i,j,k+1)-var%re(i,j,k)
              zero(4) = -var%re(i,j,k)*z(k+1)/denom(4,i,j,k) + &
                         var%re(i,j,k+1)*z(k)/denom(4,i,j,k)
              m(1) = (z(k)-z(k+1))/(zero(1)-zero(3))
              m(2) = (zero(2)-zero(4))/(x(i+1)-x(i))
              xp = (zero(4)-x(i)*m(2)-z(k)+zero(1)*m(1))/(m(1)-m(2))
              zp = xp*m(1)+z(k)-zero(1)*m(1)

              write (unit_no, '(3e17.9)') xp, y(j), zp
            end if
          end do
        end do
      end do
      
      write (unit_no, *) "# i,j,k --> i,j,k+1 --> i,j+1,k+1 --> i,j+1,k"
      do k=z_start,z_end
        if ((k==0) .or. (k==nz1)) cycle
        do j=jsta,jend
          if ((j==0) .or. (j==ny1)) cycle
          do i=1,nx1-1
            if (((var%re(i,j,k)*var%re(i,j,k+1) < 0.0) .and. &
                 (var%im(i,j,k)*var%im(i,j,k+1) >= 0.0)) .and. &
                ((var%im(i,j,k+1)*var%im(i,j+1,k+1) < 0.0) .and. &
                 (var%re(i,j,k+1)*var%re(i,j+1,k+1) >= 0.0)) .and. &
                ((var%re(i,j+1,k+1)*var%re(i,j+1,k) < 0.0) .and. &
                 (var%im(i,j+1,k+1)*var%im(i,j+1,k) >= 0.0)) .and. &
                ((var%im(i,j+1,k)*var%im(i,j,k) < 0.0) .and. &
                 (var%re(i,j+1,k)*var%re(i,j,k) >= 0.0)) ) then
              denom(1,i,j,k) = var%re(i,j,k)-var%re(i,j,k+1)
              zero(1) = -var%re(i,j,k+1)*z(k)/denom(1,i,j,k) + &
                         var%re(i,j,k)*z(k+1)/denom(1,i,j,k)
              denom(2,i,j,k) = var%im(i,j,k+1)-var%im(i,j+1,k+1)
              zero(2) = -var%im(i,j+1,k+1)*y(j)/denom(2,i,j,k) + &
                         var%im(i,j,k+1)*y(j+1)/denom(2,i,j,k)
              denom(3,i,j,k) = var%re(i,j+1,k+1)-var%re(i,j+1,k)
              zero(3) = -var%re(i,j+1,k)*z(k+1)/denom(3,i,j,k) + &
                         var%re(i,j+1,k+1)*z(k)/denom(3,i,j,k)
              denom(4,i,j,k) = var%im(i,j+1,k)-var%im(i,j,k)
              zero(4) = -var%im(i,j,k)*y(j+1)/denom(4,i,j,k) + &
                         var%im(i,j+1,k)*y(j)/denom(4,i,j,k)
              m(1) = (y(j)-y(j+1))/(zero(1)-zero(3))
              m(2) = (zero(2)-zero(4))/(z(k+1)-z(k))
              zp = (zero(4)-z(k)*m(2)-y(j)+zero(1)*m(1))/(m(1)-m(2))
              yp = zp*m(1)+y(j)-zero(1)*m(1)
              
              write (unit_no, '(3e17.9)') x(i), yp, zp
            else if (((var%im(i,j,k)*var%im(i,j,k+1) < 0.0) .and. &
                      (var%re(i,j,k)*var%re(i,j,k+1) >= 0.0)) .and. &
                     ((var%re(i,j,k+1)*var%re(i,j+1,k+1) < 0.0) .and. &
                      (var%im(i,j,k+1)*var%im(i,j+1,k+1) >= 0.0)) .and. &
                     ((var%im(i,j+1,k+1)*var%im(i,j+1,k) < 0.0) .and. &
                      (var%re(i,j+1,k+1)*var%re(i,j+1,k) >= 0.0)) .and. &
                     ((var%re(i,j+1,k)*var%re(i,j,k) < 0.0) .and. &
                      (var%im(i,j+1,k)*var%im(i,j,k) >= 0.0)) ) then
              denom(1,i,j,k) = var%im(i,j,k)-var%im(i,j,k+1)
              zero(1) = -var%im(i,j,k+1)*z(k)/denom(1,i,j,k) + &
                         var%im(i,j,k)*z(k+1)/denom(1,i,j,k)
              denom(2,i,j,k) = var%re(i,j,k+1)-var%re(i,j+1,k+1)
              zero(2) = -var%re(i,j+1,k+1)*y(j)/denom(2,i,j,k) + &
                         var%re(i,j,k+1)*y(j+1)/denom(2,i,j,k)
              denom(3,i,j,k) = var%im(i,j+1,k+1)-var%im(i,j+1,k)
              zero(3) = -var%im(i,j+1,k)*z(k+1)/denom(3,i,j,k) + &
                         var%im(i,j+1,k+1)*z(k)/denom(3,i,j,k)
              denom(4,i,j,k) = var%re(i,j+1,k)-var%re(i,j,k)
              zero(4) = -var%re(i,j,k)*y(j+1)/denom(4,i,j,k) + &
                         var%re(i,j+1,k)*y(j)/denom(4,i,j,k)
              m(1) = (y(j)-y(j+1))/(zero(1)-zero(3))
              m(2) = (zero(2)-zero(4))/(z(k+1)-z(k))
              zp = (zero(4)-z(k)*m(2)-y(j)+zero(1)*m(1))/(m(1)-m(2))
              yp = zp*m(1)+y(j)-zero(1)*m(1)
              
              write (unit_no, '(3e17.9)') x(i), yp, zp
            end if
          end do
        end do
      end do
    end if
  
    close (unit_no)

    return
  end subroutine get_extra_zeros

  subroutine get_re_im_zeros(in_var, p)
    ! Find where the real and imaginary parts separately go to zero
    use parameters
    use variables, only : re_im, unit_no
    use ic, only : x, y, z
    implicit none

    complex, dimension(0:nx1,jsta-2:jend+2,ksta-2:kend+2), intent(in) :: in_var
    integer, intent(in) :: p
    type (re_im) :: var
    real :: zero
    real, dimension(0:nx1,jsta:jend,ksta:kend) :: denom
    integer :: i, j, k
    !integer, parameter :: z_start=nz/2, z_end=nz/2
    integer :: z_start, z_end

    z_start=ksta
    z_end=kend

    allocate(var%re(0:nx1,jsta-2:jend+2,ksta-2:kend+2))
    allocate(var%im(0:nx1,jsta-2:jend+2,ksta-2:kend+2))

    open (unit_no, status='unknown', &
                   file=proc_dir//'re_zeros'//itos(p)//'.dat')

    var%re = real(in_var)
    var%im = aimag(in_var)

    write (unit_no, *) "# i,j,k --> i+1,j,k"

    do k=z_start,z_end
      if ((k==0) .or. (k==nz1)) cycle
      do j=jsta,jend
        if ((j==0) .or. (j==ny1)) cycle
        do i=1,nx1-1
          if ((var%re(i,j,k) == 0.0) .or. &
              (var%re(i,j,k)*var%re(i+1,j,k) < 0.0)) then
            denom(i,j,k) = var%re(i,j,k)-var%re(i+1,j,k)
            if (denom(i,j,k) == 0.0) cycle
            zero = -var%re(i+1,j,k)*x(i)/denom(i,j,k) + &
                    var%re(i,j,k)*x(i+1)/denom(i,j,k)
            write (unit_no, '(3e17.9)') zero, y(j), z(k)
          end if
        end do
      end do
    end do
    
    write (unit_no, *) "# i,j,k --> i,j+1,k"

    do k=z_start,z_end
      if ((k==0) .or. (k==nz1)) cycle
      do j=jsta,jend
        if ((j==0) .or. (j==ny1)) cycle
        do i=1,nx1-1
          if ((var%re(i,j,k) == 0.0) .or. &
              (var%re(i,j,k)*var%re(i,j+1,k) < 0.0)) then
            denom(i,j,k) = var%re(i,j,k)-var%re(i,j+1,k)
            if (denom(i,j,k) == 0.0) cycle
            zero = -var%re(i,j+1,k)*y(j)/denom(i,j,k) + &
                    var%re(i,j,k)*y(j+1)/denom(i,j,k)
            write (unit_no, '(3e17.9)') x(i), zero, z(k)
          end if
        end do
      end do
    end do
    
    if (z_start /= z_end) then
      write (unit_no, *) "# i,j,k --> i,j,k+1"

      do k=z_start,z_end
        if ((k==0) .or. (k==nz1)) cycle
        do j=jsta,jend
          if ((j==0) .or. (j==ny1)) cycle
          do i=1,nx1-1
            if ((var%re(i,j,k) == 0.0) .and. &
                (var%re(i,j,k)*var%re(i,j,k+1) < 0.0)) then
              denom(i,j,k) = var%re(i,j,k)-var%re(i,j,k+1)
              if (denom(i,j,k) == 0.0) cycle
              zero = -var%re(i,j,k+1)*z(k)/denom(i,j,k) + &
                      var%re(i,j,k)*z(k+1)/denom(i,j,k)
              write (unit_no, '(3e17.9)') x(i), y(j), zero
            end if
          end do
        end do
      end do
    end if

    close (unit_no)

    ! Barrier here to make sure some processes don't try to open the new file
    ! without it having been previously closed
    call MPI_BARRIER(MPI_COMM_WORLD, ierr)
    
    open (unit_no, status='unknown', &
                   file=proc_dir//'im_zeros'//itos(p)//'.dat')
                      
    write (unit_no, *) "# i,j,k --> i+1,j,k"
    
    do k=z_start,z_end
      if ((k==0) .or. (k==nz1)) cycle
      do j=jsta,jend
        if ((j==0) .or. (j==ny1)) cycle
        do i=1,nx1-1
          if ((var%im(i,j,k) == 0.0) .or. &
              (var%im(i,j,k)*var%im(i+1,j,k) < 0.0)) then
            denom(i,j,k) = var%im(i,j,k)-var%im(i+1,j,k)
            if (denom(i,j,k) == 0.0) cycle
            zero = -var%im(i+1,j,k)*x(i)/denom(i,j,k) + &
                    var%im(i,j,k)*x(i+1)/denom(i,j,k)
            write (unit_no, '(3e17.9)') zero, y(j), z(k)
          end if
        end do
      end do
    end do
    
    write (unit_no, *) "# i,j,k --> i,j+1,k"

    do k=z_start,z_end
      if ((k==0) .or. (k==nz1)) cycle
      do j=jsta,jend
        if ((j==0) .or. (j==ny1)) cycle
        do i=1,nx1-1
          if ((var%im(i,j,k) == 0.0) .or. &
              (var%im(i,j,k)*var%im(i,j+1,k) < 0.0)) then
            denom(i,j,k) = var%im(i,j,k)-var%im(i,j+1,k)
            if (denom(i,j,k) == 0.0) cycle
            zero = -var%im(i,j+1,k)*y(j)/denom(i,j,k) + &
                    var%im(i,j,k)*y(j+1)/denom(i,j,k)
            write (unit_no, '(3e17.9)') x(i), zero, z(k)
          end if
        end do
      end do
    end do
    
    if (z_start /= z_end) then
      write (unit_no, *) "# i,j,k --> i,j,k+1"

      do k=z_start,z_end
      if ((k==0) .or. (k==nz1)) cycle
        do j=jsta,jend
        if ((j==0) .or. (j==ny1)) cycle
          do i=1,nx1-1
            if ((var%im(i,j,k) == 0.0) .and. &
                (var%im(i,j,k)*var%im(i,j,k+1) < 0.0)) then
              denom(i,j,k) = var%im(i,j,k)-var%im(i,j,k+1)
              if (denom(i,j,k) == 0.0) cycle
              zero = -var%im(i,j,k+1)*z(k)/denom(i,j,k) + &
                      var%im(i,j,k)*z(k+1)/denom(i,j,k)
              write (unit_no, '(3e17.9)') x(i), y(j), zero
            end if
          end do
        end do
      end do
    end if

    close (unit_no)

    return
  end subroutine get_re_im_zeros
  
  subroutine save_linelength(t, in_var)
    ! Save the total vortex line length
    use parameters
    use variables, only : linelength
    implicit none

    complex, dimension(0:nx1,jsta-2:jend+2,ksta-2:kend+2), intent(in) :: in_var
    real, intent(in) :: t
    real :: tmp, length

    ! Get the line length on each individual process
    tmp = linelength(t, in_var)

    ! Sum the line length over all processes and send it to process 0
    call MPI_REDUCE(tmp, length, 1, MPI_REAL, MPI_SUM, 0, &
                    MPI_COMM_WORLD, ierr) 

    if (myrank == 0) then
      write (13, '(2e17.9)') t, length
    end if

    return
  end subroutine save_linelength

  subroutine diag(old2, old, new, p)
    use parameters
    use variables
    use ic, only : x, y, z
    implicit none
    
    integer, intent(in) :: p
    complex, dimension(0:nx1,jsta-2:jend+2,ksta-2:kend+2), intent(in) :: old, &
                                                                         old2
    complex, dimension(0:nx1,jsta:jend,ksta:kend),         intent(in) :: new
    complex, dimension(0:nx1,jsta:jend,ksta:kend) :: lhs, rhs
    real :: zpos
    integer :: i, j, k
    
    lhs = 0.5*(new-old2(:,jsta:jend,ksta:kend))/dt
    
    rhs = 0.5*(eye+0.01) * ( laplacian(old) + &
                           (1.0-abs(old(:,jsta:jend,ksta:kend))**2)*&
                                    old(:,jsta:jend,ksta:kend) )

    zpos = nz/2

    do k=ksta,kend
      if (k==zpos) then
        open (unit_no, status='unknown', file=proc_dir//'diag'//itos(p)//'.dat')
        do i=0,nx1
          write (unit_no, '(3e17.9)') (x(i), y(j), &
                 abs(rhs(i,j,zpos)-lhs(i,j,zpos)), j=jsta,jend)
          write (unit_no, *)
        end do
        close (unit_no)
        exit
      end if
    end do

    return
  end subroutine diag
    
end module io
