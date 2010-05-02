/**Summary statistics such as mean, median, sum, variance, skewness, kurtosis.
 * Except for median and median absolute deviation, which cannot be calculated
 * online, all summary statistics have both an input range interface and an
 * output range interface.
 *
 * Bugs:  This whole module assumes that input will be doubles or types implicitly
 *        convertible to double.  No allowances are made for user-defined numeric
 *        types such as BigInts.  This is necessary for simplicity.  However,
 *        if you have a function that converts your data to doubles, most of
 *        these functions work with any input range, so you can simply map
 *        this function onto your range.
 *
 * Author:  David Simcha
 */
 /*
 * License:
 * Boost Software License - Version 1.0 - August 17th, 2003
 *
 * Permission is hereby granted, free of charge, to any person or organization
 * obtaining a copy of the software and accompanying documentation covered by
 * this license (the "Software") to use, reproduce, display, distribute,
 * execute, and transmit the Software, and to prepare derivative works of the
 * Software, and to permit third-parties to whom the Software is furnished to
 * do so, all subject to the following:
 *
 * The copyright notices in the Software and this entire statement, including
 * the above license grant, this restriction and the following disclaimer,
 * must be included in all copies of the Software, in whole or in part, and
 * all derivative works of the Software, unless such copies or derivative
 * works are solely in the form of machine-executable object code generated by
 * a source language processor.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE, TITLE AND NON-INFRINGEMENT. IN NO EVENT
 * SHALL THE COPYRIGHT HOLDERS OR ANYONE DISTRIBUTING THE SOFTWARE BE LIABLE
 * FOR ANY DAMAGES OR OTHER LIABILITY, WHETHER IN CONTRACT, TORT OR OTHERWISE,
 * ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 */


module dstats.summary;

import std.algorithm, std.functional, std.conv, std.range, std.array,
    std.traits, std.math;

import dstats.sort, dstats.base, dstats.alloc;

version(unittest) {
    import std.stdio, dstats.random;

    void main() {
    }
}

/**Finds median of an input range in O(N) time on average.  In the case of an
 * even number of elements, the mean of the two middle elements is returned.
 * This is a convenience founction designed specifically for numeric types,
 * where the averaging of the two middle elements is desired.  A more general
 * selection algorithm that can handle any type with a total ordering, as well
 * as selecting any position in the ordering, can be found at
 * dstats.sort.quickSelect() and dstats.sort.partitionK().
 * Allocates memory, does not reorder input data.*/
double median(T)(T data)
if(doubleInput!(T)) {
    // Allocate once on TempAlloc if possible, i.e. if we know the length.
    // This can be done on TempAlloc.  Otherwise, have to use GC heap
    // and appending.
    auto dataDup = tempdup(data);
    scope(exit) TempAlloc.free;
    return medianPartition(dataDup);
}

/**Median finding as in median(), but will partition input data such that
 * elements less than the median will have smaller indices than that of the
 * median, and elements larger than the median will have larger indices than
 * that of the median. Useful both for its partititioning and to avoid
 * memory allocations.  Requires a random access range with swappable
 * elements.*/
double medianPartition(T)(T data)
if(isRandomAccessRange!(T) &&
   is(ElementType!(T) : double) &&
   hasSwappableElements!(T) &&
   dstats.base.hasLength!(T))
{
    if(data.length == 0) {
        return double.nan;
    }
    // Upper half of median in even length case is just the smallest element
    // with an index larger than the lower median, after the array is
    // partially sorted.
    if(data.length == 1) {
        return data[0];
    } else if(data.length & 1) {  //Is odd.
        return cast(double) partitionK(data, data.length / 2);
    } else {
        auto lower = partitionK(data, data.length / 2 - 1);
        auto upper = ElementType!(T).max;

        // Avoid requiring slicing to be supported.
        foreach(i; data.length / 2..data.length) {
            if(data[i] < upper) {
                upper = data[i];
            }
        }
        return lower * 0.5 + upper * 0.5;
    }
}

unittest {
    float brainDeadMedian(float[] foo) {
        qsort(foo);
        if(foo.length & 1)
            return foo[$ / 2];
        return (foo[$ / 2] + foo[$ / 2 - 1]) / 2;
    }

    float[] test = new float[1000];
    uint upperBound, lowerBound;
    foreach(testNum; 0..1000) {
        foreach(ref e; test) {
            e = uniform(0f, 1000f);
        }
        do {
            upperBound = uniform(0u, test.length);
            lowerBound = uniform(0u, test.length);
        } while(lowerBound == upperBound);
        if(lowerBound > upperBound) {
            swap(lowerBound, upperBound);
        }
        auto quickRes = median(test[lowerBound..upperBound]);
        auto accurateRes = brainDeadMedian(test[lowerBound..upperBound]);

        // Off by some tiny fraction in even N case because of division.
        // No idea why, but it's too small a rounding error to care about.
        assert(approxEqual(quickRes, accurateRes));
    }

    // Make sure everything works with lowest common denominator range type.
    struct Count {
        uint num;
        uint upTo;
        uint front() {
            return num;
        }
        void popFront() {
            num++;
        }
        bool empty() {
            return num >= upTo;
        }
    }

    Count a;
    a.upTo = 100;
    assert(approxEqual(median(a), 49.5));
    writeln("Passed median unittest.");
}

/**Plain old data holder struct for median, median absolute deviation.
 * Alias this'd to the median absolute deviation member.
 */
struct MedianAbsDev {
    double median;
    double medianAbsDev;

    this(this) {}  // Workaround for bug 2943

    alias medianAbsDev this;
}

/**Calculates the median absolute deviation of a dataset.  This is the median
 * of all absolute differences from the median of the dataset.
 *
 * Returns:  A MedianAbsDev struct that contains the median (since it is
 * computed anyhow) and the median absolute deviation.
 *
 * Notes:  No bias correction is used in this implementation, since using
 * one would require assumptions about the underlying distribution of the data.
 */
MedianAbsDev medianAbsDev(T)(T data)
if(doubleInput!(T)) {
    auto dataDup = tempdup(data);
    immutable med = medianPartition(dataDup);
    immutable len = dataDup.length;
    TempAlloc.free;

    double[] devs = newStack!double(len);

    size_t i = 0;
    foreach(elem; data) {
        devs[i++] = abs(med - elem);
    }
    auto ret = medianPartition(devs);
    TempAlloc.free;
    return MedianAbsDev(med, ret);
}

unittest {
    assert(approxEqual(medianAbsDev([7,1,8,2,8,1,9,2,8,4,5,9].dup), 2.5L));
    assert(approxEqual(medianAbsDev([8,6,7,5,3,0,999].dup), 2.0L));
    writeln("Passed medianAbsDev unittest.");
}

/**Output range to calculate the mean online.  Getter for mean costs a branch to
 * check for N == 0.  This struct uses O(1) space and does *NOT* store the
 * individual elements.
 *
 * Note:  This struct can implicitly convert to the value of the mean.
 *
 * Examples:
 * ---
 * Mean summ;
 * summ.put(1);
 * summ.put(2);
 * summ.put(3);
 * summ.put(4);
 * summ.put(5);
 * assert(summ.mean == 3);
 * ---*/
struct Mean {
private:
    double result = 0;
    double k = 0;

public:
    /// Allow implicit casting to double, by returning the current mean.
    alias mean this;

    ///
    void put(double element) nothrow {
        result += (element - result) / ++k;
    }

    /**Adds the contents of rhs to this instance.
     *
     * Examples:
     * ---
     * Mean mean1, mean2, combined;
     * foreach(i; 0..5) {
     *     mean1.put(i);
     * }
     *
     * foreach(i; 5..10) {
     *     mean2.put(i);
     * }
     *
     * mean1.put(mean2);
     *
     * foreach(i; 0..10) {
     *     combined.put(i);
     * }
     *
     * assert(approxEqual(combined.mean, mean1.mean));
     * ---
     */
     void put(const ref typeof(this) rhs) nothrow {
         immutable totalN = k + rhs.k;
         result = result * (k / totalN) + rhs.result * (rhs.k / totalN);
         k = totalN;
     }

    ///
    double sum() const pure nothrow {
        return result * k;
    }

    ///
    double mean() const pure nothrow {
        return (k == 0) ? double.nan : result;
    }

    ///
    double N() const pure nothrow {
        return k;
    }

    ///
    string toString() const {
        return to!(string)(mean);
    }
}

/**Finds the arithmetic mean of any input range whose elements are implicitly
 * convertible to double.*/
Mean mean(T)(T data)
if(doubleIterable!(T)) {

    static if(isRandomAccessRange!T && dstats.base.hasLength!T) {
        // This is optimized for maximum instruction level parallelism:
        // The loop is unrolled such that there are 1 / (nILP)th the data
        // dependencies of the naive algorithm.
        enum nILP = 8;

        Mean ret;
        size_t i = 0;
        if(data.length > 2 * nILP) {
            double k = 0;
            double[nILP] means = 0;
            for(; i + nILP < data.length; i += nILP) {
                immutable kNeg1 = 1 / ++k;

                foreach(j; 0..nILP) {
                    means[j] += (data[i + j] - means[j]) * kNeg1;
                }
            }

            ret.k = k;
            ret.result = means[0];
            foreach(m; means[1..$]) {
                ret.put( Mean(m, k));
            }
        }

        // Handle the remainder.
        for(; i < data.length; i++) {
            ret.put(data[i]);
        }
        return ret;

    } else {
        // Just submit everything to a single Mean struct and return it.
        Mean meanCalc;

        foreach(element; data) {
            meanCalc.put(element);
        }
        return meanCalc;
    }
}

///
struct GeometricMean {
private:
    Mean m;
public:
    ///Allow implicit casting to double, by returning current geometric mean.
    alias geoMean this;

    ///
    void put(double element) nothrow {
        m.put(log2(element));
    }

    /// Combine two GeometricMean's.
    void put(const ref typeof(this) rhs) nothrow {
        m.put(rhs.m);
    }

    ///
    double geoMean() const pure nothrow {
        return exp2(m.mean);
    }

    ///
    double N() const pure nothrow {
        return m.k;
    }

    ///
    string toString() const {
        return to!(string)(geoMean);
    }
}

///
double geometricMean(T)(T data)
if(doubleIterable!(T)) {
    // This is relatively seldom used and the log function is the bottleneck
    // anyhow, not worth ILP optimizing.
    GeometricMean m;
    foreach(elem; data) {
        m.put(elem);
    }
    return m.geoMean;
}

unittest {
    string[] data = ["1", "2", "3", "4", "5"];
    auto foo = map!(to!(uint, string))(data);

    auto result = geometricMean(map!(to!(uint, string))(data));
    assert(approxEqual(result, 2.60517));

    Mean mean1, mean2, combined;
    foreach(i; 0..5) {
      mean1.put(i);
    }

    foreach(i; 5..10) {
      mean2.put(i);
    }

    mean1.put(mean2);

    foreach(i; 0..10) {
      combined.put(i);
    }

    assert(approxEqual(combined.mean, mean1.mean));
    assert(combined.N == mean1.N);

    writeln("Passed geometricMean unittest.");
}


/**Finds the sum of an input range whose elements implicitly convert to double.
 * User has option of making U a different type than T to prevent overflows
 * on large array summing operations.  However, by default, return type is
 * T (same as input type).*/
U sum(T, U = Unqual!(IterType!(T)))(T data)
if(doubleIterable!(T)) {

    static if(isRandomAccessRange!T && dstats.base.hasLength!T) {
        enum nILP = 8;
        U[nILP] sum = 0;

        size_t i = 0;
        if(data.length > 2 * nILP) {

            for(; i + nILP < data.length; i += nILP) {
                foreach(j; 0..nILP) {
                    sum[j] += data[i + j];
                }
            }

            foreach(j; 1..nILP) {
                sum[0] += sum[j];
            }
        }

        for(; i < data.length; i++) {
            sum[0] += data[i];
        }

        return sum[0];
    } else {
        U sum = 0;
        foreach(elem; data) {
            sum += elem;
        }

        return sum;
    }
}

unittest {
    assert(sum([1,2,3,4,5,6,7,8,9,10][]) == 55);
    assert(sum(filter!"true"([1,2,3,4,5,6,7,8,9,10][])) == 55);
    assert(sum(cast(int[]) [1,2,3,4,5])==15);
    assert(approxEqual( sum(cast(int[]) [40.0, 40.1, 5.2]), 85.3));
    assert(mean(cast(int[]) [1,2,3]) == 2);
    assert(mean(cast(int[]) [1.0, 2.0, 3.0]) == 2.0);
    assert(mean([1, 2, 5, 10, 17][]) == 7);
    assert(mean([1, 2, 5, 10, 17][]).sum == 35);
    assert(approxEqual(mean([8,6,7,5,3,0,9,3,6,2,4,3,6][]).mean, 4.769231));

    // Test the OO struct a little, since we're using the new ILP algorithm.
    Mean m;
    m.put(1);
    m.put(2);
    m.put(5);
    m.put(10);
    m.put(17);
    assert(m.mean == 7);

    foreach(i; 0..100) {
        // Monte carlo test the unrolled version.
        auto foo = randArray!rNorm(uniform(5, 100), 0, 1);
        auto res1 = mean(foo);
        Mean res2;
        foreach(elem; foo) {
            res2.put(elem);
        }

        foreach(ti, elem; res1.tupleof) {
            assert(approxEqual(elem, res2.tupleof[ti]));
        }
    }

    writeln("Passed sum/mean unittest.");
}


/**Output range to compute mean, stdev, variance online.  Getter methods
 * for stdev, var cost a few floating point ops.  Getter for mean costs
 * a single branch to check for N == 0.  Relatively expensive floating point
 * ops, if you only need mean, try Mean.  This struct uses O(1) space and
 * does *NOT* store the individual elements.
 *
 * Note:  This struct can implicitly convert to a Mean struct.
 *
 * References: Computing Higher-Order Moments Online.
 * http://people.xiph.org/~tterribe/notes/homs.html
 *
 * Examples:
 * ---
 * MeanSD summ;
 * summ.put(1);
 * summ.put(2);
 * summ.put(3);
 * summ.put(4);
 * summ.put(5);
 * assert(summ.mean == 3);
 * assert(summ.stdev == sqrt(2.5));
 * assert(summ.var == 2.5);
 * ---*/
struct MeanSD {
private:
    double _mean = 0;
    double _var = 0;
    double _k = 0;
public:
    ///
    void put(double element) nothrow {
        immutable kMinus1 = _k;
        immutable delta = element - _mean;
        immutable deltaN = delta / ++_k;

        _mean += deltaN;
        _var += kMinus1 * deltaN * delta;
    }

    /// Combine two MeanSD's.
    void put(const ref typeof(this) rhs) nothrow {
        if(_k == 0) {
            foreach(ti, elem; rhs.tupleof) {
                this.tupleof[ti] = elem;
            }

            return;
        } else if(rhs._k == 0) {
            return;
        }

        immutable totalN = _k + rhs._k;
        immutable delta = rhs.mean - mean;
        _mean = _mean * (_k / totalN) + rhs._mean * (rhs._k / totalN);

        _var = _var + rhs._var + (_k / totalN * rhs._k * delta * delta);
        _k = totalN;
    }

    ///
    double sum() const pure nothrow {
        return _k * _mean;
    }

    ///
    double mean() const pure nothrow {
        return (_k == 0) ? double.nan : _mean;
    }

    ///
    double stdev() const pure nothrow {
        return sqrt(var);
    }

    ///
    double var() const pure nothrow {
        return (_k < 2) ? double.nan : _var / (_k - 1);
    }

    // Undocumented on purpose b/c it's for internal use only.
    double mse() const pure nothrow {
        return (_k < 2) ? double.nan : _var / _k;
    }

    ///
    double N() const pure nothrow {
        return _k;
    }

    /**Converts this struct to a Mean struct.  Also called when an
     * implicit conversion via alias this takes place.
     */
    Mean toMean() const pure nothrow {
        return Mean(_mean, _k);
    }

    ///
    string toString() const {
        return text("N = ", cast(ulong) _k, "\nMean = ", mean, "\nVariance = ",
               var, "\nStdev = ", stdev);
    }
}

/**Convenience function that puts all elements of data into a MeanSD struct,
 * then returns this struct.*/
MeanSD meanStdev(T)(T data)
if(doubleIterable!(T)) {

    MeanSD ret;

    static if(isRandomAccessRange!T && dstats.base.hasLength!T) {
        // Optimize for instruction level parallelism.
        enum nILP = 6;
        double k = 0;
        double[nILP] means = 0;
        double[nILP] variances = 0;
        size_t i = 0;

        if(data.length > 2 * nILP) {
            for(; i + nILP < data.length; i += nILP) {
                immutable kMinus1 = k;
                immutable kNeg1 = 1 / ++k;

                foreach(j; 0..nILP) {
                    immutable double delta = data[i + j] - means[j];
                    immutable deltaN = delta * kNeg1;

                    means[j] += deltaN;
                    variances[j] += kMinus1 * deltaN * delta;
                }
            }

            ret._mean = means[0];
            ret._var = variances[0];
            ret._k = k;

            foreach(j; 1..nILP) {
                ret.put( MeanSD(means[j], variances[j], k));
            }
        }

        // Handle remainder.
        for(; i < data.length; i++) {
            ret.put(data[i]);
        }
    } else {
        foreach(elem; data) {
            ret.put(elem);
        }
    }
    return ret;
}

/**Finds the variance of an input range with members implicitly convertible
 * to doubles.*/
double variance(T)(T data)
if(doubleIterable!(T)) {
    return meanStdev(data).var;
}

/**Calculate the standard deviation of an input range with members
 * implicitly converitble to double.*/
double stdev(T)(T data)
if(doubleIterable!(T)) {
    return meanStdev(data).stdev;
}

unittest {
    auto res = meanStdev(cast(int[]) [3, 1, 4, 5]);
    assert(approxEqual(res.stdev, 1.7078));
    assert(approxEqual(res.mean, 3.25));
    res = meanStdev(cast(double[]) [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0]);
    assert(approxEqual(res.stdev, 2.160247));
    assert(approxEqual(res.mean, 4));
    assert(approxEqual(res.sum, 28));

    MeanSD mean1, mean2, combined;
    foreach(i; 0..5) {
      mean1.put(i);
    }

    foreach(i; 5..10) {
      mean2.put(i);
    }

    mean1.put(mean2);

    foreach(i; 0..10) {
      combined.put(i);
    }

    assert(approxEqual(combined.mean, mean1.mean));
    assert(approxEqual(combined.stdev, mean1.stdev));
    assert(combined.N == mean1.N);
    assert(approxEqual(combined.mean, 4.5));
    assert(approxEqual(combined.stdev, 3.027650));

    foreach(i; 0..100) {
        // Monte carlo test the unrolled version.
        auto foo = randArray!rNorm(uniform(5, 100), 0, 1);
        auto res1 = meanStdev(foo);
        MeanSD res2;
        foreach(elem; foo) {
            res2.put(elem);
        }

        foreach(ti, elem; res1.tupleof) {
            assert(approxEqual(elem, res2.tupleof[ti]));
        }

        MeanSD resCornerCase;  // Test corner cases where one of the N's is 0.
        resCornerCase.put(res1);
        MeanSD dummy;
        resCornerCase.put(dummy);
        foreach(ti, elem; res1.tupleof) {
            assert(elem == resCornerCase.tupleof[ti]);
        }
    }

    writefln("Passed variance/standard deviation unittest.");
}

/**Output range to compute mean, stdev, variance, skewness, kurtosis, min, and
 * max online. Using this struct is relatively expensive, so if you just need
 * mean and/or stdev, try MeanSD or Mean. Getter methods for stdev,
 * var cost a few floating point ops.  Getter for mean costs a single branch to
 * check for N == 0.  Getters for skewness and kurtosis cost a whole bunch of
 * floating point ops.  This struct uses O(1) space and does *NOT* store the
 * individual elements.
 *
 * Note:  This struct can implicitly convert to a MeanSD.
 *
 * References: Computing Higher-Order Moments Online.
 * http://people.xiph.org/~tterribe/notes/homs.html
 *
 * Examples:
 * ---
 * Summary summ;
 * summ.put(1);
 * summ.put(2);
 * summ.put(3);
 * summ.put(4);
 * summ.put(5);
 * assert(summ.N == 5);
 * assert(summ.mean == 3);
 * assert(summ.stdev == sqrt(2.5));
 * assert(summ.var == 2.5);
 * assert(approxEqual(summ.kurtosis, -1.9120));
 * assert(summ.min == 1);
 * assert(summ.max == 5);
 * assert(summ.sum == 15);
 * ---*/
struct Summary {
private:
    double _mean = 0;
    double _m2 = 0;
    double _m3 = 0;
    double _m4 = 0;
    double _k = 0;
    double _min = double.infinity;
    double _max = -double.infinity;
public:
    ///
    void put(double element) nothrow {
        immutable kMinus1 = _k;
        immutable kNeg1 = 1.0 / ++_k;
        _min = (element < _min) ? element : _min;
        _max = (element > _max) ? element : _max;

        immutable delta = element - mean;
        immutable deltaN = delta * kNeg1;
        _mean += deltaN;

        _m4 += kMinus1 * deltaN * (_k * _k - 3 * _k + 3) * deltaN * deltaN * delta +
            6 * _m2 * deltaN * deltaN - 4 * deltaN * _m3;
        _m3 += kMinus1 * deltaN * (_k - 2) * deltaN * delta - 3 * delta * _m2 * kNeg1;
        _m2 += kMinus1 * deltaN * delta;
    }

    /// Combine two Summary's.
    void put(const ref typeof(this) rhs) nothrow {
        if(_k == 0) {
            foreach(ti, elem; rhs.tupleof) {
                this.tupleof[ti] = elem;
            }

            return;
        } else if(rhs._k == 0) {
            return;
        }

        immutable totalN = _k + rhs._k;
        immutable delta = rhs.mean - mean;
        immutable deltaN = delta / totalN;
        _mean = _mean * (_k / totalN) + rhs._mean * (rhs._k / totalN);

        _m4 = _m4 + rhs._m4 +
            deltaN * _k * deltaN * rhs._k * deltaN * delta *
            (_k * _k - _k * rhs._k + rhs._k * rhs._k) +
            6 * deltaN * _k * deltaN * _k * rhs._m2 +
            6 * deltaN * rhs._k * deltaN * rhs._k * _m2 +
            4 * deltaN * _k * rhs._m3 -
            4 * deltaN * rhs._k * _m3;

        _m3 = _m3 + rhs._m3 + deltaN * _k * deltaN * rhs._k * (_k - rhs._k) +
            3 * deltaN * _k * rhs._m2 -
            3 * deltaN * rhs._k * _m2;

        _m2 = _m2 + rhs._m2 + (_k / totalN * rhs._k * delta * delta);

        _k = totalN;
        _max = (_max > rhs._max) ? _max : rhs._max;
        _min = (_min < rhs._min) ? _min : rhs._min;
    }

    ///
    double sum() const pure nothrow {
        return _mean * _k;
    }

    ///
    double mean() const pure nothrow {
        return (_k == 0) ? double.nan : _mean;
    }

    ///
    double stdev() const pure nothrow {
        return sqrt(var);
    }

    ///
    double var() const pure nothrow {
        return (_k == 0) ? double.nan : _m2 / (_k - 1);
    }

    ///
    double skewness() const pure nothrow {
        immutable sqM2 = sqrt(_m2);
        return _m3 / (sqM2 * sqM2 * sqM2) * sqrt(_k);
    }

    ///
    double kurtosis() const pure nothrow {
        return _m4 / _m2 * _k  / _m2 - 3;
    }

    ///
    double N() const pure nothrow {
        return _k;
    }

    ///
    double min() const pure nothrow {
        return _min;
    }

    ///
    double max() const pure nothrow {
        return _max;
    }

    /**Converts this struct to a MeanSD.  Called via alias this when an
     * implicit conversion is attetmpted.
     */
    MeanSD toMeanSD() const pure nothrow {
        return MeanSD(_mean, _m2, _k);
    }

    alias toMeanSD this;

    ///
    string toString() const {
        return text("N = ", roundTo!long(_k),
                  "\nMean = ", mean,
                  "\nVariance = ", var,
                  "\nStdev = ", stdev,
                  "\nSkewness = ", skewness,
                  "\nKurtosis = ", kurtosis,
                  "\nMin = ", _min,
                  "\nMax = ", _max);
    }
}

unittest {
    // Everything else is tested indirectly through kurtosis, skewness.  Test
    // put(typeof(this)).

    Summary mean1, mean2, combined;
    foreach(i; 0..5) {
      mean1.put(i);
    }

    foreach(i; 5..10) {
      mean2.put(i);
    }

    mean1.put(mean2);

    foreach(i; 0..10) {
      combined.put(i);
    }

    foreach(ti, elem; mean1.tupleof) {
        assert(approxEqual(elem, combined.tupleof[ti]));
    }

    Summary summCornerCase;  // Case where one N is zero.
    summCornerCase.put(mean1);
    Summary dummy;
    summCornerCase.put(dummy);
    foreach(ti, elem; summCornerCase.tupleof) {
        assert(elem == mean1.tupleof[ti]);
    }
}

/**Excess kurtosis relative to normal distribution.  High kurtosis means that
 * the variance is due to infrequent, large deviations from the mean.  Low
 * kurtosis means that the variance is due to frequent, small deviations from
 * the mean.  The normal distribution is defined as having kurtosis of 0.
 * Input must be an input range with elements implicitly convertible to double.*/
double kurtosis(T)(T data)
if(doubleIterable!(T)) {
    // This is too infrequently used and has too much ILP within a single
    // iteration to be worth ILP optimizing.
    Summary kCalc;
    foreach(elem; data) {
        kCalc.put(elem);
    }
    return kCalc.kurtosis;
}

unittest {
    // Values from Matlab.
    assert(approxEqual(kurtosis([1, 1, 1, 1, 10].dup), 0.25));
    assert(approxEqual(kurtosis([2.5, 3.5, 4.5, 5.5].dup), -1.36));
    assert(approxEqual(kurtosis([1,2,2,2,2,2,100].dup), 2.1657));
    writefln("Passed kurtosis unittest.");
}

/**Skewness is a measure of symmetry of a distribution.  Positive skewness
 * means that the right tail is longer/fatter than the left tail.  Negative
 * skewness means the left tail is longer/fatter than the right tail.  Zero
 * skewness indicates a symmetrical distribution.  Input must be an input
 * range with elements implicitly convertible to double.*/
double skewness(T)(T data)
if(doubleIterable!(T)) {
    // This is too infrequently used and has too much ILP within a single
    // iteration to be worth ILP optimizing.
    Summary sCalc;
    foreach(elem; data) {
        sCalc.put(elem);
    }
    return sCalc.skewness;
}

unittest {
    // Values from Octave.
    assert(approxEqual(skewness([1,2,3,4,5].dup), 0));
    assert(approxEqual(skewness([3,1,4,1,5,9,2,6,5].dup), 0.5443));
    assert(approxEqual(skewness([2,7,1,8,2,8,1,8,2,8,4,5,9].dup), -0.0866));

    // Test handling of ranges that are not arrays.
    string[] stringy = ["3", "1", "4", "1", "5", "9", "2", "6", "5"];
    auto intified = map!(to!(int, string))(stringy);
    assert(approxEqual(skewness(intified), 0.5443));
    writeln("Passed skewness test.");
}

/**Convenience function.  Puts all elements of data into a Summary struct,
 * and returns this struct.*/
Summary summary(T)(T data)
if(doubleIterable!(T)) {
    // This is too infrequently used and has too much ILP within a single
    // iteration to be worth ILP optimizing.
    Summary summ;
    foreach(elem; data) {
        summ.put(elem);
    }
    return summ;
}
// Just a convenience function for a well-tested struct.  No unittest really
// necessary.  (Famous last words.)

///
struct ZScore(T) if(isForwardRange!(T) && is(ElementType!(T) : double)) {
private:
    T range;
    double mean;
    double sdNeg1;

    double z(double elem) {
        return (elem - mean) * sdNeg1;
    }

public:
    this(T range) {
        this.range = range;
        auto msd = meanStdev(range);
        this.mean = msd.mean;
        this.sdNeg1 = 1.0 / msd.stdev;
    }

    this(T range, double mean, double sd) {
        this.range = range;
        this.mean = mean;
        this.sdNeg1 = 1.0 / sd;
    }

    ///
    double front() {
        return z(range.front);
    }

    ///
    void popFront() {
        range.popFront;
    }

    ///
    bool empty() {
        return range.empty;
    }

    static if(isRandomAccessRange!(T)) {
        ///
        double opIndex(size_t index) {
            return z(range[index]);
        }
    }

    static if(isBidirectionalRange!(T)) {
        ///
        double back() {
            return z(range.back);
        }

        ///
        void popBack() {
            range.popBack;
        }
    }

    static if(dstats.base.hasLength!(T)) {
        ///
        size_t length() {
            return range.length;
        }
    }
}

/**Returns a range with whatever properties T has (forward range, random
 * access range, bidirectional range, hasLength, etc.),
 * of the z-scores of the underlying
 * range.  A z-score of an element in a range is defined as
 * (element - mean(range)) / stdev(range).
 *
 * Notes:
 *
 * If the data contained in the range is a sample of a larger population,
 * rather than an entire population, then technically, the results output
 * from the ZScore range are T statistics, not Z statistics.  This is because
 * the sample mean and standard deviation are only estimates of the population
 * parameters.  This does not affect the mechanics of using this range,
 * but it does affect the interpretation of its output.
 *
 * Accessing elements of this range is fairly expensive, as a
 * floating point multiply is involved.  Also, constructing this range is
 * costly, as the entire input range has to be iterated over to find the
 * mean and standard deviation.
 */
ZScore!(T) zScore(T)(T range)
if(isForwardRange!(T) && doubleInput!(T)) {
    return ZScore!(T)(range);
}

/**Allows the construction of a ZScore range with precomputed mean and
 * stdev.
 */
ZScore!(T) zScore(T)(T range, double mean, double sd)
if(isForwardRange!(T) && doubleInput!(T)) {
    return ZScore!(T)(range, mean, sd);
}

unittest {
    int[] arr = [1,2,3,4,5];
    auto m = mean(arr);
    auto sd = stdev(arr);
    auto z = zScore(arr);

    size_t pos = 0;
    foreach(elem; z) {
        assert(approxEqual(elem, (arr[pos++] - m) / sd));
    }

    assert(z.length == 5);
    foreach(i; 0..z.length) {
        assert(approxEqual(z[i], (arr[i] - m) / sd));
    }
    writeln("Passed zScore test.");
}



// Verify that there are no TempAlloc memory leaks anywhere in the code covered
// by the unittest.  This should always be the last unittest of the module.
unittest {
    auto TAState = TempAlloc.getState;
    assert(TAState.used == 0);
    assert(TAState.nblocks < 2);
}
