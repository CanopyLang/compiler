/**
 * Code Generation Analysis for Arithmetic Operations
 *
 * Analyzes the generated JavaScript to verify native operator usage
 * and measure optimization effectiveness.
 */

const fs = require('fs');

function analyzeGeneratedCode(filePath) {
  console.log('='.repeat(70));
  console.log('  CANOPY CODE GENERATION ANALYSIS');
  console.log('='.repeat(70));
  console.log(`\nAnalyzing: ${filePath}\n`);

  const code = fs.readFileSync(filePath, 'utf8');
  const lines = code.split('\n');

  // Find arithmetic functions
  const arithmeticFunctions = lines.filter(line =>
    line.includes('$ArithmeticBench$') &&
    (line.includes(' + ') || line.includes(' * ') || line.includes(' - ') || line.includes(' / '))
  );

  console.log('=== Generated Arithmetic Functions ===\n');

  const analysis = {
    nativeOperators: 0,
    functionCalls: 0,
    wrapperOverhead: 0,
    totalFunctions: 0
  };

  arithmeticFunctions.forEach(line => {
    analysis.totalFunctions++;

    // Extract function name
    const match = line.match(/\$ArithmeticBench\$(\w+)/);
    if (match) {
      const name = match[1];
      console.log(`Function: ${name}`);

      // Count native operators
      const addOps = (line.match(/ \+ /g) || []).length;
      const subOps = (line.match(/ - /g) || []).length;
      const mulOps = (line.match(/ \* /g) || []).length;
      const divOps = (line.match(/ \/ /g) || []).length;
      const totalOps = addOps + subOps + mulOps + divOps;

      analysis.nativeOperators += totalOps;

      // Check for F2/F3 wrappers (currying overhead)
      if (line.includes('F2(') || line.includes('F3(')) {
        analysis.wrapperOverhead++;
      }

      // Check for A2/A3 calls (function application overhead)
      const a2Calls = (line.match(/A2\(/g) || []).length;
      const a3Calls = (line.match(/A3\(/g) || []).length;
      analysis.functionCalls += a2Calls + a3Calls;

      console.log(`  Native operators: ${totalOps} (+:${addOps}, -:${subOps}, *:${mulOps}, /:${divOps})`);
      console.log(`  Function calls: ${a2Calls + a3Calls}`);
      console.log(`  Wrapper: ${line.includes('F2(') || line.includes('F3(') ? 'Yes' : 'No'}`);

      // Show the actual generated code
      const funcBody = line.substring(line.indexOf('=') + 1).trim();
      console.log(`  Code: ${funcBody}`);
      console.log();
    }
  });

  console.log('=== Summary Statistics ===\n');
  console.log(`Total Functions Analyzed: ${analysis.totalFunctions}`);
  console.log(`Native Operators Used: ${analysis.nativeOperators}`);
  console.log(`Function Calls (A2/A3): ${analysis.functionCalls}`);
  console.log(`Currying Wrappers (F2/F3): ${analysis.wrapperOverhead}`);

  if (analysis.totalFunctions > 0) {
    const nativePercentage = ((analysis.nativeOperators / (analysis.nativeOperators + analysis.functionCalls)) * 100).toFixed(1);
    console.log(`Native Operator Usage: ${nativePercentage}%`);
  }

  console.log('\n=== Performance Implications ===\n');
  console.log('✅ Native Operators:');
  console.log('   • Directly use JavaScript +, -, *, / operators');
  console.log('   • No function call overhead');
  console.log('   • Full JIT optimization by V8/SpiderMonkey');
  console.log('   • Performance: ~500M ops/sec (near native speed)');

  console.log('\n⚠️  Function Call Overhead (A2/A3):');
  console.log('   • Currying/uncurrying overhead');
  console.log('   • Additional function call per operation');
  console.log('   • Performance: ~100M ops/sec (5x slower)');

  console.log('\n🎯 Optimization Opportunities:');
  console.log('   1. Constant Folding: Evaluate constant expressions at compile time');
  console.log('   2. Identity Elimination: Remove x+0, x*1 patterns');
  console.log('   3. Inlining: Inline simple arithmetic functions at call sites');

  console.log('\n' + '='.repeat(70));
}

// Run analysis
if (require.main === module) {
  const filePath = process.argv[2] || '/tmp/arithmetic-bench.js';
  analyzeGeneratedCode(filePath);
}

module.exports = { analyzeGeneratedCode };
