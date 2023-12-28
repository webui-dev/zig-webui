// This file gets called like follow:
// `Index.html` ->
//  `http://localhost:xxx/deno_test.ts?foo=123&bar=456` ->
//   `deno run --allow-all --unstable "deno_test.ts" "foo=123&bar=456"`

// Import parse()
import { parse } from 'https://deno.land/std/flags/mod.ts';

// Get Query (HTTP GET)
const args = parse(Deno.args);
const query = args._[0] as string;

// Variables
let foo: string = '';
let bar: string = '';

// Read Query
const params = new URLSearchParams(query);
for (const [key, value] of params.entries()) {
	if (key == 'foo') foo = value; // 123
	else if (key == 'bar') bar = value; // 456
}

console.error('foo + bar = ' + (parseInt(foo) + parseInt(bar))); // 579
