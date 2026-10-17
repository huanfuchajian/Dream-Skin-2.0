// 输入校验错误：code 是机器可读的原因，field 指向出错字段。
export class InputError extends Error {
  constructor(code, field) {
    super(field ? `${code} @ ${field}` : code);
    this.name = 'InputError';
    this.code = code;
    this.field = field;
  }
}
