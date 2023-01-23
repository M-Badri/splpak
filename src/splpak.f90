!*****************************************************************************************
!>
!  This package contains routines for fitting
!  (least squares) a multidimensional cubic spline
!  to arbitrarily located data.  It also contains
!  routines for evaluating this spline (or its
!  partial derivatives) at any point.
!
!  Coefficient calculation is performed in
!  subroutines [[splcc]] or [[splcw]] and evaluation is
!  performed by functions [[splfe]] or [[splde]].
!
!### Usage
!
!  Package SPLPAK contains four user entries --
!  SPLCC, SPLCW, SPLFE, AND SPLDE.
!
!  The user first calls SPLCC by
!```fortran
!    CALL SPLCC (NDIM,XDATA,L1XDAT,YDATA,NDATA,
!                XMIN,XMAX,NODES,XTRAP,COEF,NCF,
!                WORK,NWRK,IERROR)
!```
!  or SPLCW by
!```fortran
!    CALL SPLCW (NDIM,XDATA,L1XDATA,YDATA,WDATA,
!                NDATA,XMIN,XMAX,NODES,XTRAP,
!                COEF,NCF,WORK,NWRK,IERROR)
!```
!  The parameter NDATA in the call to SPLCW
!  enables the user to weight some of the data
!  points more heavily than others.  Both
!  routines return a set of coefficients in the
!  array COEF.  These coefficients are
!  subsequently used in the computation of
!  function values and partial derivatives.
!  To compute values on the spline approximation
!  the user then calls SPLFE or SPLDE any
!  number of times in any order provided that
!  the values of the inputs, NDIM, COEF, XMIN,
!  XMAX, and NODES, are preserved between calls.
!
!  SPLFE and SPLDE are called in the following way:
!```fortran
!    F = SPLFE (NDIM,X,COEF,XMIN,XMAX,NODES,IERROR)
!```
!  or
!```fortran
!    F = SPLDE (NDIM,X,NDERIV,COEF,XMIN,XMAX,NODES,IERROR)
!```
!  The routine SPLFE returns an interpolated
!  value at the point defined by the array X.
!  SPLDE affords the user the additional
!  capability of calculating an interpolated
!  value for one of several partial derivatives
!  specified by the array NDERIV.
!
!### History
!  * Developed in 1972-73 by NCAR's Scientific Computing Division.
!  * Cleaned up and added to the Ngmath library in 1998.
!  * Latest revision to the Fortran 77 code: August, 1998
!  * Jacob Williams : Jan 2023 : modernized this code.
!
!### License
!    Copyright (C) 2000
!    University Corporation for Atmospheric Research
!    All Rights Reserved
!    The use of this Software is governed by a License Agreement.

    module splpak_module

    use iso_fortran_env, only: output_unit
    use iso_fortran_env, only: wp => real64

    implicit none

    contains
!*****************************************************************************************

!*****************************************************************************************
!>
!  This routine does basis function computations for natural
!  splines.  This routine is called by routines SPLCW and SPLDE
!  to compute ICOL and BASM, which are defined as follows:
!
!     The MDIM indices in IB (defined through common) determine
!     a specific node in the node grid (see routine SPLCC for a
!     description of the node grid).  Every node is associated
!     with an MDIM-dimensional basis function and a corresponding
!     column in the least squares matrix (or element of the
!     coefficient vector).  The column index (which may be thought
!     of as a linear address for the MDIM-dimensional node grid)
!     corresponding to the specified node is computed as ICOL.  The
!     associated basis function evaluated at X (an MDIM-vector) is
!     computed as BASM (a scalar).
!
!  In case NDERIV is not all zero, BASM will not be the value of
!  the basis function but rather a partial derivative of that
!  function as follows:
!
!     The order of the partial derivative in the direction of the
!     IDIM coordinate is NDERIV(IDIM) (for IDIM <= MDIM).  This
!     routine will compute incorrect values if NDERIV(IDIM) is not
!     in the range 0 to 2.
!
!  The technique of this routine is to transform the independent
!  variable in each dimension such that the nodes fall on
!  suitably chosen integers.  On this transformed space, the
!  1-dimensional basis functions and their derivatives have a
!  particularly simple form.  The desired MDIM-dimensional basis
!  function (or any of its partial derivatives) is computed as
!  a product of such 1-dimensional functions (tensor product
!  method of defining multi-dimensional splines).  The values
!  which determine the location of the nodes, and hence the
!  above transform, are passed through common and the argument
!  list.

subroutine bascmp(x,nderiv,xmin,nodes,icol,basm)

    real(wp),intent(in) :: x(4)
    integer,intent(in) :: nderiv(4)
    real(wp),intent(in) :: xmin(4)
    integer,intent(in) :: nodes(4)
    integer,intent(out) :: icol
    real(wp),intent(out) :: basm

    real(wp) :: xb,bas1,z,fact,z1
    integer :: idim,mdmid,ntyp,ngo

    real(wp) :: dx(4),dxin(4)
    integer :: mdim,ib(4),ibmn(4),ibmx(4)
    common /splcomd/ dx,dxin,mdim,ib,ibmn,ibmx

    save

    ! ICOL will be a linear address corresponding to the indices in IB.
    icol = 0

    ! BASM will be M-dimensional basis function evaluated at X.
    basm = 1.0_wp
    do idim = 1,mdim

        ! Compute ICOL by Horner's method.
        mdmid = mdim + 1 - idim
        icol = nodes(mdmid)*icol + ib(mdmid)

        ! NGO depends upon function type and NDERIV.
        ntyp = 1

        ! Function type 1 (left linear) for IB = 0 or 1.
        if (ib(idim)>1) then
            ntyp = 2
            ! Function type 2 (chapeau function) for 2 LT IB LT NODES-2.
            if (ib(idim)>=nodes(idim)-2) then
                ntyp = 3
            end if
        end if

        ! Function type 3 (right linear) for IB = NODES-2 or NODES-1.
        ngo = 3*ntyp + nderiv(idim) - 2

        !  XB is X value of node IB (center of basis function).
        xb = xmin(idim) + real(ib(idim),wp)*dx(idim)

        !  BAS1 will be the 1-dimensional basis function evaluated at X.
        bas1 = 0.0_wp

        select case (ngo)

        case(4)

            !  Function type 2 (chapeau function).
            !
            !  Transform so that XB is at the origin and the other nodes are at
            !  the integers.
            z = abs(dxin(idim)* (x(idim)-xb)) - 2.0_wp

            !  This chapeau function is then that unique cubic spline which is
            !  identically zero for ABS(Z) GE 2 and is 1 at the origin.  This
            !  function is the general interior node basis function.
            if (z<0.0_wp) then
                bas1 = -0.25_wp*z**3
                z = z + 1.0_wp
                if (z<0.0_wp) then
                    bas1 = bas1 + z**3
                end if
            end if

        case(5)

            !  1st derivative.
            z = x(idim) - xb
            fact = dxin(idim)
            if (z<0.0_wp) fact = -fact
            z = fact*z - 2.0_wp
            if (z<0.0_wp) then
                bas1 = -0.75_wp*z**2
                z = z + 1.0_wp
                if (z<0.0_wp) then
                    bas1 = bas1 + 3.0_wp*z**2
                end if
                bas1 = fact*bas1
            end if

        case(6) ! 108

            !  2nd derivative.
            fact = dxin(idim)
            z = fact*abs(x(idim)-xb) - 2.0_wp
            if (z<0.0_wp) then
                bas1 = -1.5_wp*z
                z = z + 1.0_wp
                if (z<0.0_wp) then
                    bas1 = bas1 + 6.0_wp*z
                end if
                bas1 = (fact**2)*bas1
            end if

        case(2,8)

            !  1st derivative.
            if (ngo==2) then
                fact = -dxin(idim)
            else if (ngo==8) then
                fact = dxin(idim)
            end if
            z = fact* (x(idim)-xb) + 2.0_wp
            if (z<0.0_wp) then
                if (z<2.0_wp) then
                    bas1 = 1.5_wp*z**2
                    z = z - 1.0_wp
                    if (z>0.0_wp) then
                        bas1 = bas1 - 3.0_wp*z**2
                    end if
                    bas1 = fact*bas1
                else
                    bas1 = 3.0_wp*fact
                end if
            end if

        case(3,9)

            !  2nd derivative.
            if (ngo==3) then
                fact = -dxin(idim)
            else if (ngo==9) then
                fact = dxin(idim)
            end if
            z = fact* (x(idim)-xb) + 2.0_wp
            z1 = z - 1.0_wp
            if (abs(z1)<1.0_wp) then
                bas1 = 3.0_wp*z
                if (z1>0.0_wp) then
                    bas1 = bas1 - 6.0_wp*z1
                end if
                bas1 = (fact**2)*bas1
            end if

        case default ! case(1,7) ! or ngo some other value (does that ever happen?)
                     !             (due to the computed goto in the original code)

            if (ngo/=7) then
                !  Function type 1 (left linear) is mirror image of function type 3.
                !
                !  Transform so that XB is at 2 and the other nodes are at the integers
                !  (with ordering reversed to form a mirror image).
                z = dxin(idim)* (xb-x(idim)) + 2.0_wp
            else
                !  Function type 3 (right linear).
                !
                !  Transform so that XB is at 2 and the other nodes are at the integers.
                z = dxin(idim)* (x(idim)-xb) + 2.0_wp
            end if

            !  This right linear function is defined to be that unique cubic spline
            !  which is identically zero for Z <= 0 and is 3*Z-3 for Z GE 2.
            !  This function (obviously having zero 2nd derivative for
            !  Z GE 2) is used for the two nodes nearest an edge in order
            !  to generate natural splines, which must by definition have
            !  zero 2nd derivative at the boundary.
            !
            !  Note that this method of generating natural splines also provides
            !  a linear extrapolation which has 2nd order continuity with
            !  the interior splines at the boundary.

            if (z>0.0_wp) then
                if (z<2.0_wp) then
                    bas1 = 0.5_wp*z**3
                    z = z - 1.0_wp
                    if (z>0.0_wp) then
                        bas1 = bas1 - z**3
                    end if
                else
                    bas1 = 3.0_wp*z - 3.0_wp
                end if
            end if

        end select

        basm = basm*bas1

    end do

    icol = icol + 1

end subroutine bascmp
!*****************************************************************************************

!*****************************************************************************************
!>
!  To print an error number and an error message
!  or just an error message.
!
!  The message is writen to `output_unit`.

subroutine cfaerr (ierr,mess)

    integer,intent(in) :: ierr !! The error number (printed only if non-zero).
    character(len=*), intent(in) :: mess !! Message to be printed.

    if (ierr /= 0) write (output_unit,'(A,I5)') ' IERR=', ierr
    write (output_unit,'(A)') trim(mess)

end subroutine cfaerr
!*****************************************************************************************

!*****************************************************************************************
!>
!  N-dimensional cubic spline coefficient
!  calculation by least squares.
!
!  The usage and arguments of this routine are
!  identical to those for [[SPLCW]] except for the
!  omission of the array of weights, `WDATA`.  See
!  entry [[SPLCW]] description for a
!  complete description.

subroutine splcc(ndim,xdata,l1xdat,ydata,ndata,xmin,xmax,nodes, &
                 xtrap,coef,ncf,work,nwrk,ierror)


    integer,intent(in) :: ndim
    integer,intent(in) :: l1xdat
    integer,intent(in) :: ncf
    integer,intent(in) :: nwrk
    integer,intent(in) :: ndata
    real(wp),intent(in) :: xdata(l1xdat,ndata)
    real(wp),intent(in) :: ydata(ndata)
    real(wp),intent(in) :: xmin(ndim)
    real(wp),intent(in) :: xmax(ndim)
    real(wp),intent(in) :: xtrap
    integer,intent(in) :: nodes(ndim)
    real(wp) :: work(nwrk)
    real(wp),intent(out) :: coef(ncf)
    integer,intent(out) :: ierror

    real(wp),dimension(1),parameter :: wdata = -1.0_wp !! indicates to [[splcw]]
                                                       !! that weights are not used

    save

    call splcw(ndim,xdata,l1xdat,ydata,wdata,ndata,xmin,xmax,&
               nodes,xtrap,coef,ncf,work,nwrk,ierror)

end subroutine splcc
!*****************************************************************************************

!*****************************************************************************************
!>
!  N-dimensional cubic spline coefficient
!  calculation by weighted least squares on
!  arbitrarily located data.
!
!  The spline (or its derivatives) may then be
!  evaluated by using function [[SPLFE]] (or [[SPLDE]]).
!
!  A grid of evenly spaced nodes in NDIM space is
!  defined by the arguments XMIN, XMAX and NODES.
!  A linear basis for the class of natural splines
!  on these nodes is formed, and a set of
!  corresponding coefficients is computed in the
!  array COEF.  These coefficients are chosen to
!  minimize the weighted sum of squared errors
!  between the spline and the arbitrarily located
!  data values described by the arguments XDATA,
!  YDATA and NDATA.  The smoothness of the spline
!  in data sparse areas is controlled by the
!  argument XTRAP.
!
!### Note
!  In order to understand the arguments of this
!  routine, one should realize that the node grid
!  need not bear any particular relation to the
!  data points.  In the theory of exact-fit
!  interpolatory splines, the nodes would in fact
!  be data locations, but in this case they serve
!  only to define the class of splines from which
!  the approximating function is chosen.  This
!  node grid is a rectangular arrangement of
!  points in NDIM space, with the restriction that
!  along any coordinate direction the nodes are
!  equally spaced.  The class of natural splines
!  on this grid of nodes (NDIM-cubic splines whose
!  2nd derivatives normal to the boundaries are 0)
!  has as many degrees of freedom as the grid has
!  nodes.  Thus the smoothness or flexibility of
!  the splines is determined by the choice of the
!  node grid.
!
!### Algorithm
!  An overdetermined system of linear equations
!  is formed -- one equation for each data point
!  plus equations for derivative constraints.
!  This system is solved using subroutine [[suprls]].
!
!### Accuracy
!  If there is exactly one data point in the
!  near vicinity of each node and no extra data,
!  the resulting spline will agree with the
!  data values to machine accuracy.  However, if
!  the problem is overdetermined or the sparse
!  data option is utilized, the accuracy is hard
!  to predict.  Basically, smooth functions
!  require fewer nodes than rough ones for the
!  same accuracy.
!
!### Timing
!  The execution time is roughly proportional
!  to `NDATA*NCOF**2` where `NCOF = NODES(1)*...*NODES(NDIM)`.

subroutine splcw(ndim,xdata,l1xdat,ydata,wdata,ndata,xmin,xmax, &
                  nodes,xtrap,coef,ncf,work,nwrk,ierror)

    integer,intent(in) :: ndim !! The dimensionality of the problem.  The
                               !! spline is a function of `NDIM` variables or
                               !! coordinates and thus a point in the
                               !! independent variable space is an `NDIM` vector.
                               !! `NDIM` must be in the range `1 <= NDIM <= 4`.
    integer,intent(in) :: l1xdat !! The length of the 1st dimension of `XDATA` in
                                 !! the calling program.  `L1XDAT` must be `>= NDIM`.
                                 !!
                                 !!#### Note:
                                 !! For 1-dimensional problems `L1XDAT` is usually 1.
    integer,intent(in) :: ncf !! The length of the array `COEF` in the calling
                              !! program.  If `NCF` is `< NODES(1)*...*NODES(NDIM)`,
                              !! a fatal error is diagnosed.
    integer,intent(in) :: nwrk !! The length of the array `WORK` in the calling
                               !! program.  If
                               !! `NCOL = NODES(1)*...*NODES(NDIM)` is the total
                               !! number of nodes, then a fatal error is
                               !! diagnosed if `NWRK` is less than
                               !! `NCOL*(NCOL+1)`.
    integer,intent(in) :: ndata !! The number of data points mentioned in the
                                !! above arguments.
    real(wp),intent(in) :: xdata(l1xdat,ndata) !! A collection of locations for the data
                                               !! values, i.e., points from the independent
                                               !! variable space.  This collection is a
                                               !! 2-dimensional array whose 1st dimension
                                               !! indexes the `NDIM` coordinates of a given point
                                               !! and whose 2nd dimension labels the data
                                               !! point.  For example, the data point with
                                               !! label `IDATA` is located at the point
                                               !! `(XDATA(1,IDATA),...,XDATA(NDIM,IDATA))` where
                                               !! the elements of this vector are the values of
                                               !! the `NDIM` coordinates.  The location, number
                                               !! and ordering of the data points is arbitrary.
                                               !! The dimension of `XDATA` is assumed to be
                                               !! `XDATA(L1XDAT,NDATA)`.
    real(wp),intent(in) :: ydata(ndata) !! A collection of data values corresponding to
                                        !! the points in `XDATA`.  `YDATA(IDATA)` is the
                                        !! data value associated with the point
                                        !! `(XDATA(1,IDATA),...,XDATA(NDIM,IDATA))` in the
                                        !! independent variable space.  The spline whose
                                        !! coefficients are computed by this routine
                                        !! approximates these data values in the least
                                        !! squares sense.  The dimension is assumed to be
                                        !! `YDATA(NDATA)`.
    real(wp),intent(in) :: wdata(:) !! A collection of weights.  `WDATA(IDATA)` is a
                                    !! weight associated with the data point
                                    !! labelled `IDATA`.  It should be non-negative,
                                    !! but may be of any magnitude.  The weights
                                    !! have the effect of forcing greater or lesser
                                    !! accuracy at a given point as follows: this
                                    !! routine chooses coefficients to minimize the
                                    !! sum over all data points of the quantity
                                    !!```fortran
                                    !!   (WDATA(IDATA)*(YDATA(IDATA) ! spline value at XDATA(IDATA)))**2.
                                    !!```
                                    !! Thus, if the reliability
                                    !! of a data point is known to be low, the
                                    !! corresponding weight may be made small
                                    !! (relative to the other weights) so that the
                                    !! sum over all data points is affected less by
                                    !! discrepencies at the unreliable point.  Data
                                    !! points with zero weight are completely
                                    !! ignored.
                                    !!
                                    !!#### Note:
                                    !! If `WDATA(1)` is `< 0`, the other
                                    !! elements of `WDATA` are not
                                    !! referenced, and all weights are
                                    !! assumed to be unity.
                                    !!
                                    !! The dimension is assumed to be `WDATA(NDATA)`
                                    !! unless `WDATA(1) < 0.`, in which case the
                                    !! dimension is assumed to be 1.
    real(wp),intent(in) :: xmin(ndim) !! A vector describing the lower extreme corner
                                      !! of the node grid.  A set of evenly spaced
                                      !! nodes is formed along each coordinate axis
                                      !! and `XMIN(IDIM)` is the location of the first
                                      !! node along the `IDIM` axis.  The dimension is
                                      !! assumed to be `XMIN(NDIM)`.
    real(wp),intent(in) :: xmax(ndim) !! A vector describing the upper extreme corner
                                      !! of the node grid.  A set of evenly spaced
                                      !! nodes is formed along each coordinate axis
                                      !! and `XMAX(IDIM)` is the location of the last
                                      !! node along the `IDIM` axis.  The dimension is
                                      !! assumed to be `XMAX(NDIM)`.
    real(wp),intent(in) :: xtrap !! A parameter to control extrapolation to data
                                 !! sparse areas.  The region described by `XMIN`
                                 !! and `XMAX` is divided into rectangles, the
                                 !! number of which is determined by `NODES`, and
                                 !! any rectangle containing a disproportionately
                                 !! small number of data points is considered to
                                 !! be data sparse (rectangle is used here to
                                 !! mean `NDIM`-dimensional rectangle).  If `XTRAP`
                                 !! is nonzero the least squares problem is
                                 !! augmented with derivative constraints in the
                                 !! data sparse areas to prevent the matrix from
                                 !! becoming poorly conditioned.  `XTRAP` serves as
                                 !! a weight for these constraints, and thus may
                                 !! be used to control smoothness in data sparse
                                 !! areas.  Experience indicates that unity is a
                                 !! good first guess for this parameter.
                                 !!
                                 !!#### Note:
                                 !! If `XTRAP` is zero, substantial
                                 !! portions of the routine will be
                                 !! skipped, but a singular matrix
                                 !! can result if large portions of
                                 !! the region are without data.
    integer,intent(in) :: nodes(ndim) !! A vector of integers describing the number of
                                      !! nodes along each axis.  `NODES(IDIM)` is the
                                      !! number of nodes (counting endpoints) along
                                      !! the `IDIM` axis and determines the flexibility
                                      !! of the spline in that coordinate direction.
                                      !! `NODES(IDIM)` must be `>= 4`, but may be as
                                      !! large as the arrays `COEF` and `WORK` allow.
                                      !! The dimension is assumed to be `NODES(NDIM)`.
                                      !!
                                      !!#### Note:
                                      !! The node grid is completely defined by
                                      !! the arguments `XMIN`, `XMAX` and `NODES`.
                                      !! The spacing of this grid in the `IDIM`
                                      !! coordinate direction is:
                                      !!```fortran
                                      !!   DX(IDIM) = (XMAX(IDIM)-XMIN(IDIM)) / (NODES(IDIM)-1).
                                      !!```
                                      !! A node in this grid may be indexed by
                                      !! an `NDIM` vector of integers
                                      !! `(IN(1),...,IN(NDIM))` where
                                      !! `1 <= IN(IDIM) <= NODES(IDIM)`.
                                      !! The location of such a node may be
                                      !! represented by an `NDIM` vector
                                      !! `(X(1),...,X(NDIM))` where
                                      !! `X(IDIM) = XMIN(IDIM) + (IN(IDIM)-1) * DX(IDIM)`.
    real(wp) :: work(nwrk) !! A workspace array for solving the least
                           !! squares matrix generated by this routine.
                           !! Its required size is a function of the total
                           !! number of nodes in the node grid.  This
                           !! total, `NCOL = NODES(1)*...*NODES(NDIM)`, is
                           !! also the number of columns in the least
                           !! squares matrix.  The length of the array `WORK`
                           !! must equal or exceed `NCOL*(NCOL+1)`.
    real(wp),intent(out) :: coef(ncf) !! The array of coefficients computed by this
                                      !! routine.  Each coefficient corresponds to a
                                      !! particular basis function which in turn
                                      !! corresponds to a node in the node grid.  This
                                      !! correspondence between the node grid and the
                                      !! array `COEF` is as if `COEF` were an
                                      !! `NDIM`-dimensional Fortran array with
                                      !! dimensions `NODES(1),...,NODES(NDIM)`, i.e., to
                                      !! store the array linearly, the leftmost
                                      !! indices are incremented most frequently.
                                      !! Hence the length of the `COEF` array must equal
                                      !! or exceed the total number of nodes, which is
                                      !! `NODES(1)*...*NODES(NDIM)`.  The computed array
                                      !! `COEF` may be used with function [[SPLFE]]
                                      !! (or [[SPLDE]]) to evaluate the spline (or its
                                      !! derivatives) at an arbitrary point in `NDIM`
                                      !! space.  The dimension is assumed to be `COEF(NCF)`.
    integer,intent(out) :: ierror !! An error flag with the following meanings:
                                  !!
                                  !! * `  0`  No error.
                                  !! * `101`  `NDIM` is < 1 or is > 4.
                                  !! * `102`  `NODES(IDIM)` is < 4 for some `IDIM`.
                                  !! * `103`  `XMIN(IDIM) = XMAX(IDIM)` for some `IDIM`.
                                  !! * `104`  `NCF` (size of `COEF`) is `< NODES(1)*...*NODES(NDIM)`.
                                  !! * `105`  `NDATA` is `< 1`.
                                  !! * `106`  `NWRK` (size of `WORK`) is too small.
                                  !! * `107`  [[suprls]] failure (usually insufficient
                                  !!   data) -- ordinarily occurs only if
                                  !!   `XTRAP` is zero or `WDATA` contains all
                                  !!   zeros.

    real(wp) :: x(4),dx(4),dxin(4)
    integer :: nderiv(4),in(4),inmx(4)
    integer :: mdim,ib(4),ibmn(4),ibmx(4)
    !  The restriction that NDIM be less than are equal to 4 can be
    !  eliminated by increasing the above dimensions, but the required
    !  length of WORK becomes quite large.

    common /splcomd/ dx,dxin,mdim,ib,ibmn,ibmx

    real(wp) :: xrng,swght,rowwt,rhs,basm,reserr,totlwt,bump,wtprrc,expect,dcwght
    integer :: ncol,idim,nod,nwrk1,mdata,nwlft,irow,&
               idata,icol,it,lserr,iin,nrect,idimc,idm,&
               jdm,inidim
    logical :: boundary

    save

    real(wp),parameter :: spcrit = 0.75_wp
        !! SPCRIT is used to determine data sparseness as follows -
        !! the weights assigned to all data points are totaled into the
        !! variable TOTLWT. (If no weights are entered, it is set to
        !! NDATA.)  Each node of the node network is assigned a
        !! rectangle (in which it is contained) and the weights of all
        !! data points which fall in that rectangle are totaled.  If that
        !! total is less than SPCRIT*EXPECT (EXPECT is defined below),
        !! then the node is ascertained to be in a data sparse location.
        !! EXPECT is that fraction of TOTLWT that would be expected by
        !! comparing the area of the rectangle with the total area under
        !! consideration.

    ierror = 0
    mdim = ndim
    if (mdim<1 .or. mdim>4) then
        ierror = 101
        call cfaerr(ierror, &
            ' splcc or splcw - NDIM is less than 1 or is greater than 4')
        return
    end if
    ncol = 1
    do idim = 1,mdim
        nod = nodes(idim)
        if (nod<4) then
            ierror = 102
            call cfaerr(ierror, &
                ' splcc or splcw - NODES(IDIM) is less than 4 for some IDIM')
            return
        end if

        !  Number of columns in least squares matrix = number of coefficients =
        !  product of nodes over all dimensions.
        ncol = ncol*nod
        xrng = xmax(idim) - xmin(idim)
        if (xrng==0.0_wp) then
            ierror = 103
            call cfaerr(ierror, &
                ' splcc or splcw - XMIN(IDIM) equals XMAX(IDIM) for some IDIM')
            return
        end if

        !  DX(IDIM) is the node spacing along the IDIM coordinate.
        dx(idim) = xrng/real(nod-1,wp)
        dxin(idim) = 1.0_wp/dx(idim)
        nderiv(idim) = 0
    end do
    if (ncol>ncf) then
        ierror = 104
        call cfaerr(ierror, &
            ' splcc or splcw - NCF (size of COEF) is too small')
        return
    end if
    nwrk1 = 1
    mdata = ndata
    if (mdata<1) then
        ierror = 105
        call cfaerr(ierror, &
            ' splcc or splcw - Ndata Is less than 1')
        return
    end if

    !  SWGHT is a local variable = XTRAP, and can be considered a smoothing
    !  weight for data sparse areas.  If SWGHT == 0, no smoothing
    !  computations are performed.
    swght = xtrap

    !  Set aside workspace for counting data points.
    if (swght/=0.0_wp) nwrk1 = ncol + 1

    !  NWLFT is the length of the remaining workspace.
    nwlft = nwrk - nwrk1 + 1
    if (nwlft<1) then
        ierror = 106
        call cfaerr(ierror, &
            ' splcc or splcw - NWRK (size of WORK) is too small')
        return
    end if
    irow = 0

    !  ROWWT is used to weight rows of the least squares matrix.
    rowwt = 1.0_wp

    !  Loop through all data points, computing a row for each.
    do idata = 1,mdata

        !  WDATA(1)<0 means weights have not been entered.  In that case,
        !  ROWWT is left equal to  1. for all points.  Otherwise ROWWT is
        !  equal to WDATA(IDATA).
        !
        !  Every element of the row, as well as the corresponding right hand
        !  side, is multiplied by ROWWT.
        if (wdata(1)>=0.0_wp) then
            rowwt = wdata(idata)
            !  Data points with 0 weight are ignored.
            if (rowwt==0.0_wp) cycle
        end if
        irow = irow + 1

        !  One row of the least squares matrix corresponds to each data
        !  point.  The right hand for that row will correspond to the
        !  function value YDATA at that point.
        rhs = rowwt*ydata(idata)
        do idim = 1,mdim
            x(idim) = xdata(idim,idata)
        end do

        !  The COEF array serves as a row of least squares matrix.
        !  Its value is zero except for columns corresponding to functions
        !  which are nonzero at X.
        do icol = 1,ncol
            coef(icol) = 0.0_wp
        end do

        !  Compute the indices of basis functions which are nonzero at X.
        !  IBMN is in the range 0 to nodes-2 and IBMX is in range 1
        !  to NODES-1.
        do idim = 1,mdim
            nod = nodes(idim)
            it = dxin(idim)* (x(idim)-xmin(idim))
            ibmn(idim) = min(max(it-1,0),nod-2)
            ib(idim) = ibmn(idim)
            ibmx(idim) = max(min(it+2,nod-1),1)
        end do

        basis_index : do
            !  Begining of basis index loop - traverse all indices corresponding
            !  to basis functions which are nonzero at X.  The indices are in
            !  IB and are passed through common to BASCMP.
            call bascmp(x,nderiv,xmin,nodes,icol,basm)

            !  BASCMP computes ICOL and BASM where BASM is the value at X of
            !  the N-dimensional basis function corresponding to column ICOL.
            coef(icol) = rowwt*basm

            !  Increment the basis indices.
            do idim = 1,mdim
                ib(idim) = ib(idim) + 1
                if (ib(idim)<=ibmx(idim)) cycle basis_index
                ib(idim) = ibmn(idim)
            end do
            exit basis_index !  End of basis index loop.
        end do basis_index

        !  Send a row of the least squares matrix to the reduction routine.
        call suprls(irow,coef,ncol,rhs,work(nwrk1),nwlft,coef,reserr,lserr)
        if (lserr/=0) then
            ierror = 107
            call cfaerr(ierror, &
                ' splcc or splcw - suprls failure (this usually indicates insufficient input data)')
        end if
    end do

    !  Row computations for all data points are now complete.
    !
    !  If SWGHT==0, the least squares matrix is complete and no
    !  smoothing rows are computed.

    if (swght/=0.0_wp) then

        !  Initialize smoothing computations for data sparse areas.
        !  Derivative constraints will always have zero right hand side.
        rhs = 0.0_wp
        nrect = 1

        !  Initialize the node indices and compute number of rectangles
        !  formed by the node network.
        do idim = 1,mdim
            in(idim) = 0
            inmx(idim) = nodes(idim) - 1
            nrect = nrect*inmx(idim)
        end do

        !  Every node is assigned an element of the workspace (set aside
        !  previously) in which data points are counted.
        do iin = 1,ncol
            work(iin) = 0.0_wp
        end do

        !  Assign each data point to a node, total the assignments for
        !  each node, and save in the workspace.
        totlwt = 0.0_wp
        do idata = 1,mdata

            ! BUMP is the weight associated with the data point.
            bump = 1.0_wp
            if (wdata(1)>=0.0_wp) bump = wdata(idata)
            if (bump==0.0_wp) cycle

            ! Find the nearest node.
            iin = 0
            do idimc = 1,mdim
                idim = mdim + 1 - idimc
                inidim = int(dxin(idim)* (xdata(idim,idata)-xmin(idim))+0.5_wp)
                ! Points not in range (+ or - 1/2 node spacing) are not counted.
                if (inidim<0 .or. inidim>inmx(idim)) cycle
                ! Compute linear address of node in workspace by Horner's method.
                iin = (inmx(idim)+1)*iin + inidim
            end do

            ! Bump counter for that node.
            work(iin+1) = work(iin+1) + bump
            totlwt = totlwt + bump
        end do

        ! Compute the expected weight per rectangle.
        wtprrc = totlwt/real(nrect,wp)

        !  IN contains indices of the node (previously initialized).
        !  IIN will be the linear address of the node in the workspace.
        iin = 0

        !  Loop through all nodes, computing derivative constraint rows
        !  for those in data sparse locations.
        !
        !  Begining of node index loop - traverse all node indices.
        !  The indices are in IN.
        node_index : do
            iin = iin + 1
            expect = wtprrc

            !  Rectangles at edge of network are smaller and hence less weight
            !  should be expected.
            do idim = 1,mdim
                if (in(idim)==0 .or. in(idim)==inmx(idim)) expect = 0.5_wp*expect
            end do

            !  The expected weight minus the actual weight serves to define
            !  data sparseness and is also used to weight the derivative
            !  constraint rows.
            !
            !  There is no constraint if not data sparse.
            if (work(iin)<spcrit*expect) then

                dcwght = expect - work(iin)
                do idim = 1,mdim
                    inidim = in(idim)

                    !  Compute the location of the node.
                    x(idim) = xmin(idim) + real(inidim,wp)*dx(idim)

                    !  Compute the indices of the basis functions which are non-zero
                    !  at the node.
                    ibmn(idim) = inidim - 1
                    ibmx(idim) = inidim + 1

                    !  Distinguish the boundaries.
                    if (inidim==0) ibmn(idim) = 0
                    if (inidim==inmx(idim)) ibmx(idim) = inmx(idim)

                    !  Initialize the basis indices.
                    ib(idim) = ibmn(idim)
                end do

                !  Multiply by the extrapolation parameter (this acts as a
                !  smoothing weight).
                dcwght = swght*dcwght

                !  The COEF array serves as a row of the least squares matrix.
                !  Its value is zero except for columns corresponding to functions
                !  which are non-zero at the node.
                do icol = 1,ncol
                    coef(icol) = 0.0_wp
                end do

                !  The 2nd derivative of a function of MDIM variables may be thought
                !  of as a symmetric MDIM x MDIM matrix of 2nd order partial
                !  derivatives.  Traverse the upper triangle of this matrix and,
                !  for each element, compute a row of the least squares matrix.

                do idm = 1,mdim
                    do jdm = idm,mdim
                        do idim = 1,mdim
                            nderiv(idim) = 0
                        end do

                        boundary = .true.
                        !  Off-diagonal elements appear twice by symmetry, so the corresponding
                        !  row is weighted by a factor of 2.
                        rowwt = 2.0_wp*dcwght
                        if (jdm==idm) then
                            !  Diagonal.
                            rowwt = dcwght
                            nderiv(jdm) = 2
                            if (in(idm)/=0 .and. in(idm)/=inmx(idm)) then
                                boundary = .false.
                            end if
                        end if
                        if (boundary) then
                            !  Node is at boundary.
                            !
                            !  Normal 2nd derivative constraint at boundary is not appropriate for
                            !  natural splines (2nd derivative 0 by definition).  Substitute
                            !  a 1st derivative constraint.
                            nderiv(idm) = 1
                            nderiv(jdm) = 1
                        end if
                        irow = irow + 1

                        basis : do
                            !  Begining of basis index loop - traverse all indices corresponding
                            !  to basis functions which are non-zero at X.
                            !  The indices are in IB and are passed through common to BASCMP.
                            call bascmp(x,nderiv,xmin,nodes,icol,basm)

                            !  BASCMP computes ICOL and BASM where BASM is the value at X of the
                            !  N-dimensional basis function corresponding to column ICOL.
                            coef(icol) = rowwt*basm

                            !  Increment the basis indices.
                            do idim = 1,mdim
                                ib(idim) = ib(idim) + 1
                                if (ib(idim)<=ibmx(idim)) cycle basis
                                ib(idim) = ibmn(idim)
                            end do

                            !  End of basis index loop.
                            exit basis
                        end do basis

                        !  Send row of least squares matrix to reduction routine.
                        call suprls(irow,coef,ncol,rhs,work(nwrk1),nwlft,coef,reserr,lserr)
                        if (lserr/=0) then
                            ierror = 107
                            call cfaerr(ierror, &
                                ' splcc or splcw - suprls failure (this usually indicates insufficient input data)')
                        end if
                    end do
                end do

            end if

            !  Increment node indices.
            do idim = 1,mdim
                in(idim) = in(idim) + 1
                if (in(idim)<=inmx(idim)) cycle node_index
                in(idim) = 0
            end do

            exit node_index !  End of node index loop.

        end do node_index

    end if

    !  Call for least squares solution in COEF array.
    irow = 0
    call suprls(irow,coef,ncol,rhs,work(nwrk1),nwlft,coef,reserr,lserr)
    if (lserr/=0) then
        ierror = 107
        call cfaerr(ierror, &
            ' splcc or splcw - suprls failure (this usually indicates insufficient input data)')
    end if

end subroutine splcw
!*****************************************************************************************

!*****************************************************************************************
!>
!  Returns an interpolated
!  value for one of several partial derivatives.
!
!### See also
!  * [[splfe]]
!
!@note The original version of this routine would stop for an error.
!      Now it just returns.

function splde(ndim,x,nderiv,coef,xmin,xmax,nodes,ierror)

    real(wp) :: splde
    integer,intent(in) :: ndim
    real(wp),intent(in) :: x(ndim)
    real(wp),intent(out) :: coef(*)
    real(wp),intent(in) :: xmin(ndim)
    real(wp),intent(in) :: xmax(ndim)
    integer,intent(in) :: nderiv(ndim)
    integer,intent(in) :: nodes(ndim)
    integer,intent(out) :: ierror

    real(wp) :: dx(4),dxin(4)
    integer :: mdim,ib(4),ibmn(4),ibmx(4)
    ! The restriction for NDIM to be <= 4 can be eliminated by increasing
    ! the above dimensions.

    common /splcomd/dx,dxin,mdim,ib,ibmn,ibmx

    real(wp) :: xrng,sum,basm
    integer :: iibmx,idim,nod,it,iib,icof

    save

    ierror = 0
    mdim = ndim
    if (mdim<1 .or. mdim>4) then
        ierror = 101
        call cfaerr(ierror, &
            ' splfe or splde - NDIM is less than 1 or greater than 4')
        return
    end if
    iibmx = 1
    do idim = 1,mdim
        nod = nodes(idim)
        if (nod<4) then
            ierror = 102
            call cfaerr(ierror, &
                ' splfe or splde - NODES(IDIM) is less than  4for some IDIM')
            return
        end if
        xrng = xmax(idim) - xmin(idim)
        if (xrng==0.0_wp) then
            ierror = 103
            call cfaerr(ierror, &
                ' splfe or splde - XMIN(IDIM) = XMAX(IDIM) for some IDIM')
            return
        end if
        if (nderiv(idim)<0 .or. nderiv(idim)>2) then
            ierror = 104
            call cfaerr(ierror, &
                ' splde - NDERIV(IDIM) IS less than 0 or greater than 2 for some IDIM')
        end if

        !  DX(IDIM) is the node spacing along the IDIM coordinate.
        dx(idim) = xrng/real(nod-1,wp)
        dxin(idim) = 1.0_wp/dx(idim)

        !  Compute indices of basis functions which are nonzero at X.
        it = dxin(idim)*(x(idim)-xmin(idim))

        !  IBMN must be in the range 0 to NODES-2.
        ibmn(idim) = min(max(it-1,0),nod-2)

        !  IBMX must be in the range 1 to NODES-1.
        ibmx(idim) = max(min(it+2,nod-1),1)
        iibmx = iibmx* (ibmx(idim)-ibmn(idim)+1)
        ib(idim) = ibmn(idim)
    end do

    sum = 0.0_wp
    iib = 0

    basis_index : do
        !  Begining of basis index loop - traverse all indices corresponding
        !  to basis functions which are nonzero at X.
        iib = iib + 1

        !  The indices are in IB and are passed through common to BASCMP.
        call bascmp(x,nderiv,xmin,nodes,icof,basm)

        !  BASCMP computes ICOF and BASM where BASM is the value at X of the
        !  N-dimensional basis function corresponding to COEF(ICOF).
        sum = sum + coef(icof)*basm
        if (iib<iibmx) then
            !  Increment the basis indices.
            do idim = 1,mdim
                ib(idim) = ib(idim) + 1
                if (ib(idim)<=ibmx(idim)) cycle basis_index
                ib(idim) = ibmn(idim)
            end do
        end if

        exit basis_index !  End of basis index loop.
    end do basis_index

    splde = sum

end function splde
!*****************************************************************************************

!*****************************************************************************************
!>
!  Returns an interpolated value at the point defined by the array X.
!
!### See also
!  * [[splde]]

function splfe(ndim,x,coef,xmin,xmax,nodes,ierror)

    real(wp) :: splfe
    integer,intent(in) :: ndim
    real(wp),intent(in) :: x(ndim)
    real(wp),intent(out) :: coef(*)
    real(wp),intent(in) :: xmin(ndim)
    real(wp),intent(in) :: xmax(ndim)
    integer,intent(in) :: nodes(ndim)
    integer,intent(out) :: ierror

    integer,dimension(4),parameter :: nderiv = [0,0,0,0]
    ! The restriction for NDIM to be <= 4 can be eliminated by
    ! increasing the above dimension and those in splde.

    save

    splfe = splde(ndim,x,nderiv,coef,xmin,xmax,nodes,ierror)

end function splfe
!*****************************************************************************************

!*****************************************************************************************
!>
!  Solve the overdetermined system of linear equations.

subroutine suprls(i,rowi,n,bi,a,nn,soln,err,ier)

    integer :: i
    integer :: nn
    integer,intent(in) :: n
    real(wp) :: rowi(n)
    real(wp) :: bi
    real(wp) :: a(nn)
    real(wp) :: soln(n)
    real(wp) :: err
    real(wp) :: errsum
    real(wp) :: s
    real(wp) :: temp
    real(wp) :: temp1
    real(wp) :: cn
    real(wp) :: sn
    integer :: ier

    integer :: iold,np1,l,ilast,il1,k,k1,nreq,j,ilj,ilnp,&
               isav,idiag,i1,i2,ii,jp1,lmkm1,j1,jdel,idj,iijd,&
               i1jd,k11,k1m1,i11,np1mk,lmk,imov,iii,iiim,iim1,&
               ilk,npk,ilii,npii
    logical :: complete_reduction !! Routine entered with `I<=0` means complete
                                  !! the reduction and store the solution in `SOLN`.

    real(wp),parameter :: tol = 1.0e-18_wp !! small number tolerance

    save

    ier = 0
    complete_reduction = i <= 0

    if (.not. complete_reduction) then

        if (i<=1) then

            !  Set up quantities on first call.
            iold = 0
            np1 = n + 1

            !  Compute how many rows can be input now.
            l = nn/np1
            ilast = 0
            il1 = 0
            k = 0
            k1 = 0
            errsum = 0.0_wp
            nreq = ((n+5)*n+2)/2

            !  Error exit if insufficient scratch storage provided.
            if (nn<nreq) then
                ier = 32
                write(*,*) 'nn   = ', nn
                write(*,*) 'nreq = ', nreq
                call cfaerr(ier, &
                            ' suprls - insufficient scratch storage provided. '//&
                            'at least ((N+5)*N+2)/2 locations needed')
                return
            end if

        end if

        !  Error exit if (I-IOLD)/=1.
        if ((i-iold)/=1) then
            ier = 35
            write(*,*) 'i    =',i
            write(*,*) 'iold =',iold
            call cfaerr(ier,' suprls - values of I not in sequence')
            return
        end if

        !  Store the row in the scratch storage.
        iold = i
        do j = 1,n
            ilj = ilast + j
            a(ilj) = rowi(j)
        end do
        ilnp = ilast + np1
        a(ilnp) = bi
        ilast = ilast + np1
        isav = i
        if (i<l) return

    end if

    main : do

        if (.not. complete_reduction) then

            if (k/=0) then
                k1 = min(k,n)
                idiag = -np1
                if (l-k==1) then
                    !  Apply rotations to zero out the single new row.
                    do j = 1,k1
                        idiag = idiag + (np1-j+2)
                        i1 = il1 + j
                        if (abs(a(i1))<=tol) then
                            s = sqrt(a(idiag)*a(idiag))
                        else if (abs(a(idiag))<tol) then
                            s = sqrt(a(i1)*a(i1))
                        else
                            s = sqrt(a(idiag)*a(idiag)+a(i1)*a(i1))
                        end if
                        if (s==0.0_wp) cycle
                        temp = a(idiag)
                        a(idiag) = s
                        s = 1.0_wp/s
                        cn = temp*s
                        sn = a(i1)*s
                        jp1 = j + 1
                        do j1 = jp1,np1
                            jdel = j1 - j
                            idj = idiag + jdel
                            temp = a(idj)
                            i1jd = i1 + jdel
                            a(idj) = cn*temp + sn*a(i1jd)
                            a(i1jd) = -sn*temp + cn*a(i1jd)
                        end do
                    end do
                else
                    !  Apply householder transformations to zero out new rows.
                    do j = 1,k1
                        idiag = idiag + (np1-j+2)
                        i1 = il1 + j
                        i2 = i1 + np1* (l-k-1)
                        s = a(idiag)*a(idiag)
                        do ii = i1,i2,np1
                            s = s + a(ii)*a(ii)
                        end do
                        if (s==0.0_wp) cycle
                        temp = a(idiag)
                        a(idiag) = sqrt(s)
                        if (temp>0.0_wp) a(idiag) = -a(idiag)
                        temp = temp - a(idiag)
                        temp1 = 1.0_wp / (temp*a(idiag))
                        jp1 = j + 1
                        do j1 = jp1,np1
                            jdel = j1 - j
                            idj = idiag + jdel
                            s = temp*a(idj)
                            do ii = i1,i2,np1
                                iijd = ii + jdel
                                s = s + a(ii)*a(iijd)
                            end do
                            s = s*temp1
                            a(idj) = a(idj) + s*temp
                            do ii = i1,i2,np1
                                iijd = ii + jdel
                                a(iijd) = a(iijd) + s*a(ii)
                            end do
                        end do
                    end do
                end if

                if (k>=n) then
                    lmkm1 = l - k

                    !  Accumulate residual sum of squares.
                    do ii = 1,lmkm1
                        ilnp = il1 + ii*np1
                        errsum = errsum + a(ilnp)*a(ilnp)
                    end do
                    if (i<=0) exit main
                    k = l
                    ilast = il1

                    !  Determine how many new rows may be input on next iteration.
                    l = k + (nn-ilast)/np1
                    return
                end if
            end if

            k11 = k1 + 1
            k1 = min(l,n)
            if (l-k/=1) then
                k1m1 = k1 - 1
                if (l>n) k1m1 = n
                i1 = il1 + k11 - np1 - 1

                !  Perform householder transformations to reduce rows to upper
                !  triangular form.
                do j = k11,k1m1
                    i1 = i1 + (np1+1)
                    i2 = i1 + (l-j)*np1
                    s = 0.0_wp
                    do ii = i1,i2,np1
                        s = s + a(ii)*a(ii)
                    end do
                    if (s==0.0_wp) cycle
                    temp = a(i1)
                    a(i1) = sqrt(s)
                    if (temp>0.0_wp) a(i1) = -a(i1)
                    temp = temp - a(i1)
                    temp1 = 1.0_wp/ (temp*a(i1))
                    jp1 = j + 1
                    i11 = i1 + np1
                    do j1 = jp1,np1
                        jdel = j1 - j
                        i1jd = i1 + jdel
                        s = temp*a(i1jd)
                        do ii = i11,i2,np1
                            iijd = ii + jdel
                            s = s + a(ii)*a(iijd)
                        end do
                        s = s*temp1
                        i1jd = i1 + jdel
                        a(i1jd) = a(i1jd) + s*temp
                        do ii = i11,i2,np1
                            iijd = ii + jdel
                            a(iijd) = a(iijd) + s*a(ii)
                        end do
                    end do
                end do
                if (l>n) then
                    np1mk = np1 - k
                    lmk = l - k
                    ! Accumulate residual sum of squares.
                    do ii = np1mk,lmk
                        ilnp = il1 + ii*np1
                        errsum = errsum + a(ilnp)*a(ilnp)
                    end do
                end if
            end if
            imov = 0
            i1 = il1 + k11 - np1 - 1

            !  Squeeze the unnecessary elements out of scratch storage to
            !  allow space for more rows.
            do ii = k11,k1
                imov = imov + (ii-1)
                i1 = i1 + np1 + 1
                i2 = i1 + np1 - ii
                do iii = i1,i2
                    iiim = iii - imov
                    a(iiim) = a(iii)
                end do
            end do
            ilast = i2 - imov
            il1 = ilast
            if (i<=0) exit main
            k = l

            !  Determine how many new rows may be input on next iteration.
            l = k + (nn-ilast)/np1
            return

        end if

        ! Complete reduction and store solution in SOLN.
        complete_reduction = .false. ! reset this flag
        l = isav

        ! Error exit if L less than N.
        if (l<n) then
            ier = 33
            call cfaerr(ier,' suprls - array has too few rows.')
            return
        end if

        ! K/=ISAV means further reduction needed.
        if (k==isav) exit main

    end do main

    ilast = (np1* (np1+1))/2 - 1
    if (a(ilast-1)==0.0_wp) then
        ! Error return if system is singular.
        ier = 34
        call cfaerr(ier,' suprls - system is singular.')
        return
    end if

    ! Solve triangular system into ROWI.
    soln(n) = a(ilast)/a(ilast-1)
    do ii = 2,n
        iim1 = ii - 1
        ilast = ilast - ii
        s = a(ilast)
        do k = 1,iim1
            ilk = ilast - k
            npk = np1 - k
            s = s - a(ilk)*soln(npk)
        end do
        ilii = ilast - ii
        if (a(ilii)==0.0_wp) then
            ! Error return if system is singular.
            ier = 34
            call cfaerr(ier,' suprls - system is singular.')
            return
        end if
        npii = np1 - ii
        soln(npii) = s/a(ilii)
    end do

    ! Store residual norm.
    err = sqrt(errsum)

end subroutine suprls
!*****************************************************************************************

!*****************************************************************************************
    end module splpak_module
!*****************************************************************************************