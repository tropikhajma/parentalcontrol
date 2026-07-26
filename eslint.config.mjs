import js from '@eslint/js';

export default [
	{
		ignores: [ 'dist/**' ]
	},
	js.configs.recommended,
	{
		files: [ '**/*.js' ],
		languageOptions: {
			ecmaVersion: 'latest',
			sourceType: 'script',
			parserOptions: {
				ecmaFeatures: {
					globalReturn: true
				}
			},
			globals: {
				E: 'readonly',
				L: 'readonly',
				N_: 'readonly',
				_: 'readonly',
				confirm: 'readonly',
				document: 'readonly',
				dom: 'readonly',
				fetch: 'readonly',
				form: 'readonly',
				rpc: 'readonly',
				sessionStorage: 'readonly',
				uci: 'readonly',
				ui: 'readonly',
				view: 'readonly'
			}
		},
		rules: {
			'no-empty': [ 'error', { allowEmptyCatch: true } ],
			'no-unused-vars': [ 'error', {
				argsIgnorePattern: '^_',
				caughtErrorsIgnorePattern: '^_'
			} ]
		}
	}
];
