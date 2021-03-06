"""
Pixelization routines



"""

#-----------------------------------------------------------------------------
# Copyright (c) 2013, yt Development Team.
#
# Distributed under the terms of the Modified BSD License.
#
# The full license is in the file COPYING.txt, distributed with this software.
#-----------------------------------------------------------------------------

import numpy as np
cimport numpy as np
cimport cython
cimport libc.math as math
from fp_utils cimport fmin, fmax, i64min, i64max, imin, imax
from yt.utilities.exceptions import YTPixelizeError
cdef extern from "stdlib.h":
    # NOTE that size_t might not be int
    void *alloca(int)

cdef extern from "pixelization_constants.h":
    enum:
        MAX_NUM_FACES

    int HEX_IND
    int HEX_NF
    np.uint8_t hex_face_defs[MAX_NUM_FACES][2][2]

    int TETRA_IND
    int TETRA_NF
    np.uint8_t tetra_face_defs[MAX_NUM_FACES][2][2]

    int WEDGE_IND
    int WEDGE_NF
    np.uint8_t wedge_face_defs[MAX_NUM_FACES][2][2]

@cython.cdivision(True)
@cython.boundscheck(False)
@cython.wraparound(False)
def pixelize_cartesian(np.ndarray[np.float64_t, ndim=1] px,
                       np.ndarray[np.float64_t, ndim=1] py,
                       np.ndarray[np.float64_t, ndim=1] pdx,
                       np.ndarray[np.float64_t, ndim=1] pdy,
                       np.ndarray[np.float64_t, ndim=1] data,
                       int cols, int rows, bounds,
                       int antialias = 1,
                       period = None,
                       int check_period = 1):
    cdef np.float64_t x_min, x_max, y_min, y_max
    cdef np.float64_t period_x = 0.0, period_y = 0.0
    cdef np.float64_t width, height, px_dx, px_dy, ipx_dx, ipx_dy
    cdef int nx, ny, ndx, ndy
    cdef int i, j, p, xi, yi
    cdef int lc, lr, rc, rr
    cdef np.float64_t lypx, rypx, lxpx, rxpx, overlap1, overlap2
    # These are the temp vars we get from the arrays
    cdef np.float64_t oxsp, oysp, xsp, ysp, dxsp, dysp, dsp
    # Some periodicity helpers
    cdef int xiter[2], yiter[2]
    cdef np.float64_t xiterv[2], yiterv[2]
    cdef np.ndarray[np.float64_t, ndim=2] my_array
    if period is not None:
        period_x = period[0]
        period_y = period[1]
    x_min = bounds[0]
    x_max = bounds[1]
    y_min = bounds[2]
    y_max = bounds[3]
    width = x_max - x_min
    height = y_max - y_min
    px_dx = width / (<np.float64_t> rows)
    px_dy = height / (<np.float64_t> cols)
    ipx_dx = 1.0 / px_dx
    ipx_dy = 1.0 / px_dy
    if rows == 0 or cols == 0:
        raise YTPixelizeError("Cannot scale to zero size")
    if px.shape[0] != py.shape[0] or \
       px.shape[0] != pdx.shape[0] or \
       px.shape[0] != pdy.shape[0] or \
       px.shape[0] != data.shape[0]:
        raise YTPixelizeError("Arrays are not of correct shape.")
    my_array = np.zeros((rows, cols), "float64")
    xiter[0] = yiter[0] = 0
    xiterv[0] = yiterv[0] = 0.0
    # Here's a basic outline of what we're going to do here.  The xiter and
    # yiter variables govern whether or not we should check periodicity -- are
    # we both close enough to the edge that it would be important *and* are we
    # periodic?
    #
    # The other variables are all either pixel positions or data positions.
    # Pixel positions will vary regularly from the left edge of the window to
    # the right edge of the window; px_dx and px_dy are the dx (cell width, not
    # half-width).  ipx_dx and ipx_dy are the inverse, for quick math.
    #
    # The values in xsp, dxsp, x_min and their y counterparts, are the
    # data-space coordinates, and are related to the data fed in.  We make some
    # modifications for periodicity.
    #
    # Inside the finest loop, we compute the "left column" (lc) and "lower row"
    # (lr) and then iterate up to "right column" (rc) and "uppeR row" (rr),
    # depositing into them the data value.  Overlap computes the relative
    # overlap of a data value with a pixel.
    with nogil:
        for p in range(px.shape[0]):
            xiter[1] = yiter[1] = 999
            oxsp = px[p]
            oysp = py[p]
            dxsp = pdx[p]
            dysp = pdy[p]
            dsp = data[p]
            if check_period == 1:
                if (oxsp - dxsp < x_min):
                    xiter[1] = +1
                    xiterv[1] = period_x
                elif (oxsp + dxsp > x_max):
                    xiter[1] = -1
                    xiterv[1] = -period_x
                if (oysp - dysp < y_min):
                    yiter[1] = +1
                    yiterv[1] = period_y
                elif (oysp + dysp > y_max):
                    yiter[1] = -1
                    yiterv[1] = -period_y
            overlap1 = overlap2 = 1.0
            for xi in range(2):
                if xiter[xi] == 999: continue
                xsp = oxsp + xiterv[xi]
                if (xsp + dxsp < x_min) or (xsp - dxsp > x_max): continue
                for yi in range(2):
                    if yiter[yi] == 999: continue
                    ysp = oysp + yiterv[yi]
                    if (ysp + dysp < y_min) or (ysp - dysp > y_max): continue
                    lc = <int> fmax(((xsp-dxsp-x_min)*ipx_dx),0)
                    lr = <int> fmax(((ysp-dysp-y_min)*ipx_dy),0)
                    # NOTE: This is a different way of doing it than in the C
                    # routines.  In C, we were implicitly casting the
                    # initialization to int, but *not* the conditional, which
                    # was allowed an extra value:
                    #     for(j=lc;j<rc;j++)
                    # here, when assigning lc (double) to j (int) it got
                    # truncated, but no similar truncation was done in the
                    # comparison of j to rc (double).  So give ourselves a
                    # bonus row and bonus column here.
                    rc = <int> fmin(((xsp+dxsp-x_min)*ipx_dx + 1), rows)
                    rr = <int> fmin(((ysp+dysp-y_min)*ipx_dy + 1), cols)
                    for i in range(lr, rr):
                        lypx = px_dy * i + y_min
                        rypx = px_dy * (i+1) + y_min
                        if antialias == 1:
                            overlap2 = ((fmin(rypx, ysp+dysp)
                                       - fmax(lypx, (ysp-dysp)))*ipx_dy)
                        if overlap2 < 0.0: continue
                        for j in range(lc, rc):
                            lxpx = px_dx * j + x_min
                            rxpx = px_dx * (j+1) + x_min
                            if antialias == 1:
                                overlap1 = ((fmin(rxpx, xsp+dxsp)
                                           - fmax(lxpx, (xsp-dxsp)))*ipx_dx)
                                if overlap1 < 0.0: continue
                                my_array[j,i] += (dsp * overlap1) * overlap2
                            else:
                                my_array[j,i] = dsp
    return my_array


@cython.cdivision(True)
@cython.boundscheck(False)
@cython.wraparound(False)
def pixelize_cylinder(np.ndarray[np.float64_t, ndim=1] radius,
                      np.ndarray[np.float64_t, ndim=1] dradius,
                      np.ndarray[np.float64_t, ndim=1] theta,
                      np.ndarray[np.float64_t, ndim=1] dtheta,
                      buff_size,
                      np.ndarray[np.float64_t, ndim=1] field,
                      extents, input_img = None):

    cdef np.ndarray[np.float64_t, ndim=2] img
    cdef np.float64_t x, y, dx, dy, r0, theta0
    cdef np.float64_t rmax, x0, y0, x1, y1
    cdef np.float64_t r_i, theta_i, dr_i, dtheta_i, dthetamin
    cdef np.float64_t costheta, sintheta
    cdef int i, pi, pj
    
    imax = radius.argmax()
    rmax = radius[imax] + dradius[imax]
          
    if input_img is None:
        img = np.zeros((buff_size[0], buff_size[1]))
        img[:] = np.nan
    else:
        img = input_img
    x0, x1, y0, y1 = extents
    dx = (x1 - x0) / img.shape[0]
    dy = (y1 - y0) / img.shape[1]
    cdef np.float64_t rbounds[2]
    cdef np.float64_t corners[8]
    # Find our min and max r
    corners[0] = x0*x0+y0*y0
    corners[1] = x1*x1+y0*y0
    corners[2] = x0*x0+y1*y1
    corners[3] = x1*x1+y1*y1
    corners[4] = x0*x0
    corners[5] = x1*x1
    corners[6] = y0*y0
    corners[7] = y1*y1
    rbounds[0] = rbounds[1] = corners[0]
    for i in range(8):
        rbounds[0] = fmin(rbounds[0], corners[i])
        rbounds[1] = fmax(rbounds[1], corners[i])
    rbounds[0] = rbounds[0]**0.5
    rbounds[1] = rbounds[1]**0.5
    # If we include the origin in either direction, we need to have radius of
    # zero as our lower bound.
    if x0 < 0 and x1 > 0:
        rbounds[0] = 0.0
    if y0 < 0 and y1 > 0:
        rbounds[0] = 0.0
    dthetamin = dx / rmax
    for i in range(radius.shape[0]):

        r0 = radius[i]
        theta0 = theta[i]
        dr_i = dradius[i]
        dtheta_i = dtheta[i]
        # Skip out early if we're offsides, for zoomed in plots
        if r0 + dr_i < rbounds[0] or r0 - dr_i > rbounds[1]:
            continue
        theta_i = theta0 - dtheta_i
        # Buffer of 0.5 here
        dthetamin = 0.5*dx/(r0 + dr_i)
        while theta_i < theta0 + dtheta_i:
            r_i = r0 - dr_i
            costheta = math.cos(theta_i)
            sintheta = math.sin(theta_i)
            while r_i < r0 + dr_i:
                if rmax <= r_i:
                    r_i += 0.5*dx 
                    continue
                y = r_i * costheta
                x = r_i * sintheta
                pi = <int>((x - x0)/dx)
                pj = <int>((y - y0)/dy)
                if pi >= 0 and pi < img.shape[0] and \
                   pj >= 0 and pj < img.shape[1]:
                    if img[pi, pj] != img[pi, pj]:
                        img[pi, pj] = 0.0
                    img[pi, pj] = field[i]
                r_i += 0.5*dx 
            theta_i += dthetamin

    return img

cdef void aitoff_thetaphi_to_xy(np.float64_t theta, np.float64_t phi,
                                np.float64_t *x, np.float64_t *y):
    cdef np.float64_t z = math.sqrt(1 + math.cos(phi) * math.cos(theta / 2.0))
    x[0] = math.cos(phi) * math.sin(theta / 2.0) / z
    y[0] = math.sin(phi) / z

@cython.cdivision(True)
@cython.boundscheck(False)
@cython.wraparound(False)
def pixelize_aitoff(np.ndarray[np.float64_t, ndim=1] theta,
                    np.ndarray[np.float64_t, ndim=1] dtheta,
                    np.ndarray[np.float64_t, ndim=1] phi,
                    np.ndarray[np.float64_t, ndim=1] dphi,
                    buff_size,
                    np.ndarray[np.float64_t, ndim=1] field,
                    extents, input_img = None,
                    np.float64_t theta_offset = 0.0,
                    np.float64_t phi_offset = 0.0):
    # http://paulbourke.net/geometry/transformationprojection/
    # longitude is -pi to pi
    # latitude is -pi/2 to pi/2
    # z^2 = 1 + cos(latitude) cos(longitude/2)
    # x = cos(latitude) sin(longitude/2) / z
    # y = sin(latitude) / z
    cdef np.ndarray[np.float64_t, ndim=2] img
    cdef int i, j, nf, fi
    cdef np.float64_t x, y, z, zb
    cdef np.float64_t dx, dy, inside
    cdef np.float64_t theta1, dtheta1, phi1, dphi1
    cdef np.float64_t theta0, phi0, theta_p, dtheta_p, phi_p, dphi_p
    cdef np.float64_t PI = np.pi
    cdef np.float64_t s2 = math.sqrt(2.0)
    cdef np.float64_t xmax, ymax, xmin, ymin
    nf = field.shape[0]
    
    if input_img is None:
        img = np.zeros((buff_size[0], buff_size[1]))
        img[:] = np.nan
    else:
        img = input_img
    # Okay, here's our strategy.  We compute the bounds in x and y, which will
    # be a rectangle, and then for each x, y position we check to see if it's
    # within our theta.  This will cost *more* computations of the
    # (x,y)->(theta,phi) calculation, but because we no longer have to search
    # through the theta, phi arrays, it should be faster.
    dx = 2.0 / (img.shape[0] - 1)
    dy = 2.0 / (img.shape[1] - 1)
    for fi in range(nf):
        theta_p = (theta[fi] + theta_offset) - PI
        dtheta_p = dtheta[fi]
        phi_p = (phi[fi] + phi_offset) - PI/2.0
        dphi_p = dphi[fi]
        # Four transformations
        aitoff_thetaphi_to_xy(theta_p - dtheta_p, phi_p - dphi_p, &x, &y)
        xmin = x
        xmax = x
        ymin = y
        ymax = y
        aitoff_thetaphi_to_xy(theta_p - dtheta_p, phi_p + dphi_p, &x, &y)
        xmin = fmin(xmin, x)
        xmax = fmax(xmax, x)
        ymin = fmin(ymin, y)
        ymax = fmax(ymax, y)
        aitoff_thetaphi_to_xy(theta_p + dtheta_p, phi_p - dphi_p, &x, &y)
        xmin = fmin(xmin, x)
        xmax = fmax(xmax, x)
        ymin = fmin(ymin, y)
        ymax = fmax(ymax, y)
        aitoff_thetaphi_to_xy(theta_p + dtheta_p, phi_p + dphi_p, &x, &y)
        xmin = fmin(xmin, x)
        xmax = fmax(xmax, x)
        ymin = fmin(ymin, y)
        ymax = fmax(ymax, y)
        # Now we have the (projected rectangular) bounds.
        xmin = (xmin + 1) # Get this into normalized image coords
        xmax = (xmax + 1) # Get this into normalized image coords
        ymin = (ymin + 1) # Get this into normalized image coords
        ymax = (ymax + 1) # Get this into normalized image coords
        x0 = <int> (xmin / dx)
        x1 = <int> (xmax / dx) + 1
        y0 = <int> (ymin / dy)
        y1 = <int> (ymax / dy) + 1
        for i in range(x0, x1):
            x = (-1.0 + i*dx)*s2*2.0
            for j in range(y0, y1):
                y = (-1.0 + j * dy)*s2
                zb = (x*x/8.0 + y*y/2.0 - 1.0)
                if zb > 0: continue
                z = (1.0 - (x/4.0)**2.0 - (y/2.0)**2.0)
                z = z**0.5
                # Longitude
                theta0 = 2.0*math.atan(z*x/(2.0 * (2.0*z*z-1.0)))
                # Latitude
                # We shift it into co-latitude
                phi0 = math.asin(z*y)
                # Now we just need to figure out which pixel contributes.
                # We do not have a fast search.
                if not (theta_p - dtheta_p <= theta0 <= theta_p + dtheta_p):
                    continue
                if not (phi_p - dphi_p <= phi0 <= phi_p + dphi_p):
                    continue
                img[i, j] = field[fi]
    return img

# This function accepts a set of vertices (for a polyhedron) that are
# assumed to be in order for bottom, then top, in the same clockwise or
# counterclockwise direction (i.e., like points 1-8 in Figure 4 of the ExodusII
# manual).  It will then either *match* or *fill* the results.  If it is
# matching, it will early terminate with a 0 or final-terminate with a 1 if the
# results match.  Otherwise, it will fill the signs with -1's and 1's to show
# the sign of the dot product of the point with the cross product of the face.
cdef int check_face_dot(int nvertices,
                        np.float64_t point[3],
                        np.float64_t **vertices,
                        np.int8_t *signs,
                        int match):
    # Because of how we are doing this, we do not *care* what the signs are or
    # how the faces are ordered, we only care if they match between the point
    # and the centroid.
    # So, let's compute these vectors.  See above where these are written out
    # for ease of use.
    cdef np.float64_t vec1[3], vec2[3], cp_vec[3], dp, npoint[3]
    cdef np.uint8_t faces[MAX_NUM_FACES][2][2], nf
    if nvertices == 4:
        faces = tetra_face_defs
        nf = TETRA_NF
    elif nvertices == 6:
        faces = wedge_face_defs
        nf = WEDGE_NF
    elif nvertices == 8:
        faces = hex_face_defs
        nf = HEX_NF
    else:
        return -1
    cdef int i, j, n, vi1a, vi1b, vi2a, vi2b
    for n in range(nf):
        vi1a = faces[n][0][0]
        vi1b = faces[n][0][1]
        vi2a = faces[n][1][0]
        vi2b = faces[n][1][1]
        # Shared vertex is vi1b and vi2b
        for i in range(3):
            vec1[i] = vertices[vi1b][i] - vertices[vi1a][i]
            vec2[i] = vertices[vi2b][i] - vertices[vi2a][i]
            npoint[i] = point[i] - vertices[vi1b][i]
        # Now the cross product of vec1 x vec2
        cp_vec[0] = vec1[1] * vec2[2] - vec1[2] * vec2[1]
        cp_vec[1] = vec1[2] * vec2[0] - vec1[0] * vec2[2]
        cp_vec[2] = vec1[0] * vec2[1] - vec1[1] * vec2[0]
        dp = 0.0
        for j in range(3):
            dp += cp_vec[j] * npoint[j]
        if match == 0:
            if dp < 0:
                signs[n] = -1
            else:
                signs[n] = 1
        else:
            if dp < 0 and signs[n] < 0:
                continue
            elif dp >= 0 and signs[n] > 0:
                continue
            else: # mismatch!
                return 0
    return 1

def pixelize_element_mesh(np.ndarray[np.float64_t, ndim=2] coords,
                      np.ndarray[np.int64_t, ndim=2] conn,
                      buff_size,
                      np.ndarray[np.float64_t, ndim=1] field,
                      extents, int index_offset = 0):
    cdef np.ndarray[np.float64_t, ndim=3] img
    img = np.zeros(buff_size, dtype="float64")
    # Two steps:
    #  1. Is image point within the mesh bounding box?
    #  2. Is image point within the mesh element?
    # Second is more intensive.  It will require a bunch of dot and cross
    # products.  We are not guaranteed that the elements will be in the correct
    # order such that cross products are pointing in right direction, so we
    # compare against the centroid of the (assumed convex) element.
    # Note that we have to have a pseudo-3D pixel buffer.  One dimension will
    # always be 1.
    cdef np.float64_t pLE[3], pRE[3]
    cdef np.float64_t LE[3], RE[3]
    cdef int use
    cdef np.int8_t *signs
    cdef np.int64_t n, i, j, k, pi, pj, pk, ci, cj, ck
    cdef np.int64_t pstart[3], pend[3]
    cdef np.float64_t ppoint[3], centroid[3], idds[3], dds[3]
    cdef np.float64_t **vertices
    cdef int nvertices = conn.shape[1]
    cdef int nf
    # Allocate our signs array
    if nvertices == 4:
        nf = TETRA_NF
    elif nvertices == 6:
        nf = WEDGE_NF
    elif nvertices == 8:
        nf = HEX_NF
    else:
        raise RuntimeError
    signs = <np.int8_t *> alloca(sizeof(np.int8_t) * nf)
    vertices = <np.float64_t **> alloca(sizeof(np.float64_t *) * nvertices)
    for i in range(nvertices):
        vertices[i] = <np.float64_t *> alloca(sizeof(np.float64_t) * 3)
    for i in range(3):
        pLE[i] = extents[i][0]
        pRE[i] = extents[i][1]
        dds[i] = (pRE[i] - pLE[i])/buff_size[i]
        if dds[i] == 0.0:
            idds[i] = 0.0
        else:
            idds[i] = 1.0 / dds[i]
    for ci in range(conn.shape[0]):
        # Fill the vertices and compute the centroid
        centroid[0] = centroid[1] = centroid[2] = 0
        LE[0] = LE[1] = LE[2] = 1e60
        RE[0] = RE[1] = RE[2] = -1e60
        for n in range(nvertices): # 8
            cj = conn[ci, n] - index_offset
            for i in range(3):
                vertices[n][i] = coords[cj, i]
                centroid[i] += coords[cj, i]
                LE[i] = fmin(LE[i], vertices[n][i])
                RE[i] = fmax(RE[i], vertices[n][i])
        centroid[0] /= nvertices
        centroid[1] /= nvertices
        centroid[2] /= nvertices
        use = 1
        for i in range(3):
            if RE[i] < pLE[i] or LE[i] >= pRE[i]:
                use = 0
                break
            pstart[i] = i64max(<np.int64_t> ((LE[i] - pLE[i])*idds[i]) - 1, 0)
            pend[i] = i64min(<np.int64_t> ((RE[i] - pLE[i])*idds[i]) + 1, img.shape[i]-1)
        if use == 0:
            continue
        # Now our bounding box intersects, so we get the extents of our pixel
        # region which overlaps with the bounding box, and we'll check each
        # pixel in there.
        # First, we figure out the dot product of the centroid with all the
        # faces.
        check_face_dot(nvertices, centroid, vertices, signs, 0)
        for pi in range(pstart[0], pend[0] + 1):
            ppoint[0] = (pi + 0.5) * dds[0] + pLE[0]
            for pj in range(pstart[1], pend[1] + 1):
                ppoint[1] = (pj + 0.5) * dds[1] + pLE[1]
                for pk in range(pstart[2], pend[2] + 1):
                    ppoint[2] = (pk + 0.5) * dds[2] + pLE[2]
                    # Now we just need to figure out if our ppoint is within
                    # our set of vertices.
                    if check_face_dot(nvertices, ppoint, vertices, signs, 1) == 0:
                        continue
                    # Else, we deposit!
                    img[pi, pj, pk] = field[ci]
    return img
