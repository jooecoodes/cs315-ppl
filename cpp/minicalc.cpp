// minicalc.cpp — MiniCalc interpreter, OOP C++17
#include <cctype>
#include <cstddef>
#include <exception>
#include <fstream>
#include <iostream>
#include <map>
#include <memory>
#include <string>
#include <utility>
#include <vector>

// ---------------------------------------------------------------------------
// Error type — carries the frozen error code. Caught at the line boundary.
// ---------------------------------------------------------------------------
class MiniCalcError : public std::exception {
public:
    explicit MiniCalcError(std::string code) : code_(std::move(code)) {}
    const char* what() const noexcept override { return code_.c_str(); }
    const std::string& code() const noexcept { return code_; }
private:
    std::string code_;
};

// ---------------------------------------------------------------------------
// Environment: a scope chain.
// Each Env owns its bindings and points at its parent. Shadowing is just
// "nearest binding wins"; popping a scope is just letting the child Env go
// out of scope — RAII as scoping.
// ---------------------------------------------------------------------------
class Env {
public:
    Env() = default;

    // Returns a new child scope binding `name` to `value`. The child keeps a
    // pointer to *this; the caller keeps this Env alive for the child's
    // lifetime — which is exactly what recursive eval does.
    Env extend(const std::string& name, long long value) const {
        Env child;
        child.parent_ = this;
        child.vars_[name] = value;
        return child;
    }

    bool lookup(const std::string& name, long long& out) const {
        auto it = vars_.find(name);
        if (it != vars_.end()) {
            out = it->second;
            return true;
        }
        return parent_ ? parent_->lookup(name, out) : false;
    }

private:
    std::map<std::string, long long> vars_;
    const Env* parent_ = nullptr;
};

// ---------------------------------------------------------------------------
// AST: expressions. Behaviour follows the class — no tag/switch dispatch.
// ---------------------------------------------------------------------------
class Expr {
public:
    virtual ~Expr() = default;
    virtual long long eval(const Env& env) const = 0;
};

class IntLit : public Expr {
public:
    explicit IntLit(long long v) : value_(v) {}
    long long eval(const Env&) const override { return value_; }
private:
    long long value_;
};

class Var : public Expr {
public:
    explicit Var(std::string name) : name_(std::move(name)) {}
    long long eval(const Env& env) const override {
        long long v;
        if (!env.lookup(name_, v)) throw MiniCalcError("UNBOUND");
        return v;
    }
private:
    std::string name_;
};

class Let : public Expr {
public:
    Let(std::string name, std::unique_ptr<Expr> e1, std::unique_ptr<Expr> e2)
        : name_(std::move(name)), e1_(std::move(e1)), e2_(std::move(e2)) {}

    long long eval(const Env& env) const override {
        // RHS sees the OUTER env; the new binding is only visible in the body.
        long long v1 = e1_->eval(env);
        Env child = env.extend(name_, v1);
        return e2_->eval(child);
    }
private:
    std::string name_;
    std::unique_ptr<Expr> e1_;
    std::unique_ptr<Expr> e2_;
};

class BinOp : public Expr {
public:
    BinOp(char op, std::unique_ptr<Expr> lhs, std::unique_ptr<Expr> rhs)
        : op_(op), lhs_(std::move(lhs)), rhs_(std::move(rhs)) {}

    long long eval(const Env& env) const override {
        long long a = lhs_->eval(env);
        long long b = rhs_->eval(env);
        switch (op_) {
            case '+': return a + b;
            case '-': return a - b;
            case '*': return a * b;
            case '/':
                if (b == 0) throw MiniCalcError("DIV0");
                return a / b;          // C++ truncates toward zero
            case '%':
                if (b == 0) throw MiniCalcError("DIV0");
                return a % b;          // C++: sign follows dividend
        }
        throw MiniCalcError("PARSE");  // unreachable
    }
private:
    char op_;
    std::unique_ptr<Expr> lhs_;
    std::unique_ptr<Expr> rhs_;
};

class Neg : public Expr {
public:
    explicit Neg(std::unique_ptr<Expr> operand) : operand_(std::move(operand)) {}
    long long eval(const Env& env) const override {
        return -operand_->eval(env);
    }
private:
    std::unique_ptr<Expr> operand_;
};

// ---------------------------------------------------------------------------
// AST: statements.
// ---------------------------------------------------------------------------
class Stmt {
public:
    virtual ~Stmt() = default;
    virtual void execute(const Env& env) const = 0;
};

class EchoStmt : public Stmt {
public:
    explicit EchoStmt(std::unique_ptr<Expr> e) : expr_(std::move(e)) {}
    void execute(const Env& env) const override {
        std::cout << expr_->eval(env) << '\n';
    }
private:
    std::unique_ptr<Expr> expr_;
};

class ExprStmt : public Stmt {
public:
    explicit ExprStmt(std::unique_ptr<Expr> e) : expr_(std::move(e)) {}
    void execute(const Env& env) const override {
        (void)expr_->eval(env);
    }
private:
    std::unique_ptr<Expr> expr_;
};

// ---------------------------------------------------------------------------
// Lexer
// ---------------------------------------------------------------------------
enum class Tok {
    INT, IDENT,
    LET, IN, ECHO,
    PLUS, MINUS, STAR, SLASH, PERCENT,
    LPAREN, RPAREN, EQUALS,
    END
};

struct Token {
    Tok type;
    std::string text;
    long long value = 0;
};

class Lexer {
public:
    explicit Lexer(const std::string& src) : src_(src), pos_(0) {}

    Token next() {
        skipWhitespace();
        if (pos_ >= src_.size()) return Token{Tok::END, "", 0};
        char c = src_[pos_];
        unsigned char uc = static_cast<unsigned char>(c);
        if (std::isdigit(uc)) return lexNumber();
        if (std::isalpha(uc) || c == '_') return lexIdent();
        switch (c) {
            case '+': ++pos_; return Token{Tok::PLUS,    "+", 0};
            case '-': ++pos_; return Token{Tok::MINUS,   "-", 0};
            case '*': ++pos_; return Token{Tok::STAR,    "*", 0};
            case '/': ++pos_; return Token{Tok::SLASH,   "/", 0};
            case '%': ++pos_; return Token{Tok::PERCENT, "%", 0};
            case '(': ++pos_; return Token{Tok::LPAREN,  "(", 0};
            case ')': ++pos_; return Token{Tok::RPAREN,  ")", 0};
            case '=': ++pos_; return Token{Tok::EQUALS,  "=", 0};
        }
        throw MiniCalcError("PARSE");
    }

private:
    void skipWhitespace() {
        while (pos_ < src_.size() &&
               std::isspace(static_cast<unsigned char>(src_[pos_]))) {
            ++pos_;
        }
    }

    Token lexNumber() {
        std::size_t start = pos_;
        while (pos_ < src_.size() &&
               std::isdigit(static_cast<unsigned char>(src_[pos_]))) {
            ++pos_;
        }
        std::string lexeme = src_.substr(start, pos_ - start);
        long long v;
        try {
            v = std::stoll(lexeme);
        } catch (...) {
            throw MiniCalcError("PARSE");
        }
        return Token{Tok::INT, std::move(lexeme), v};
    }

    Token lexIdent() {
        std::size_t start = pos_;
        while (pos_ < src_.size()) {
            unsigned char uc = static_cast<unsigned char>(src_[pos_]);
            if (std::isalnum(uc) || src_[pos_] == '_') ++pos_;
            else break;
        }
        std::string id = src_.substr(start, pos_ - start);
        if (id == "let")  return Token{Tok::LET,  std::move(id), 0};
        if (id == "in")   return Token{Tok::IN,   std::move(id), 0};
        if (id == "echo") return Token{Tok::ECHO, std::move(id), 0};
        return Token{Tok::IDENT, std::move(id), 0};
    }

    const std::string& src_;
    std::size_t pos_;
};

std::vector<Token> tokenize(const std::string& line) {
    Lexer lex(line);
    std::vector<Token> tokens;
    for (;;) {
        Token t = lex.next();
        bool end = (t.type == Tok::END);
        tokens.push_back(std::move(t));
        if (end) break;
    }
    return tokens;
}

// ---------------------------------------------------------------------------
// Parser: recursive descent over the token vector.
// ---------------------------------------------------------------------------
class Parser {
public:
    explicit Parser(std::vector<Token> tokens) : tokens_(std::move(tokens)) {}

    std::unique_ptr<Stmt> parseStatement() {
        std::unique_ptr<Stmt> stmt;
        if (peek().type == Tok::ECHO) {
            consume();
            stmt = std::make_unique<EchoStmt>(parseExpr());
        } else {
            stmt = std::make_unique<ExprStmt>(parseExpr());
        }
        if (peek().type != Tok::END) throw MiniCalcError("PARSE");
        return stmt;
    }

private:
    const Token& peek() const { return tokens_[pos_]; }
    Token consume() { return tokens_[pos_++]; }

    std::unique_ptr<Expr> parseExpr() {
        if (peek().type == Tok::LET) {
            consume();
            if (peek().type != Tok::IDENT) throw MiniCalcError("PARSE");
            std::string name = consume().text;
            if (peek().type != Tok::EQUALS) throw MiniCalcError("PARSE");
            consume();
            auto e1 = parseExpr();
            if (peek().type != Tok::IN) throw MiniCalcError("PARSE");
            consume();
            auto e2 = parseExpr();
            return std::make_unique<Let>(std::move(name),
                                         std::move(e1), std::move(e2));
        }
        return parseAdd();
    }

    std::unique_ptr<Expr> parseAdd() {
        auto left = parseMul();
        for (;;) {
            Tok t = peek().type;
            if (t != Tok::PLUS && t != Tok::MINUS) break;
            char op = (t == Tok::PLUS) ? '+' : '-';
            consume();
            auto right = parseMul();
            left = std::make_unique<BinOp>(op, std::move(left), std::move(right));
        }
        return left;
    }

    std::unique_ptr<Expr> parseMul() {
        auto left = parseUnary();
        for (;;) {
            Tok t = peek().type;
            if (t != Tok::STAR && t != Tok::SLASH && t != Tok::PERCENT) break;
            char op = (t == Tok::STAR) ? '*' : (t == Tok::SLASH) ? '/' : '%';
            consume();
            auto right = parseUnary();
            left = std::make_unique<BinOp>(op, std::move(left), std::move(right));
        }
        return left;
    }

    std::unique_ptr<Expr> parseUnary() {
        if (peek().type == Tok::MINUS) {
            consume();
            return std::make_unique<Neg>(parseUnary());
        }
        return parsePrimary();
    }

    std::unique_ptr<Expr> parsePrimary() {
        const Token& t = peek();
        if (t.type == Tok::INT) {
            long long v = t.value;
            consume();
            return std::make_unique<IntLit>(v);
        }
        if (t.type == Tok::IDENT) {
            std::string name = t.text;
            consume();
            return std::make_unique<Var>(std::move(name));
        }
        if (t.type == Tok::LPAREN) {
            consume();
            auto e = parseExpr();
            if (peek().type != Tok::RPAREN) throw MiniCalcError("PARSE");
            consume();
            return e;
        }
        throw MiniCalcError("PARSE");
    }

    std::vector<Token> tokens_;
    std::size_t pos_ = 0;
};

// ---------------------------------------------------------------------------
// Driver
// ---------------------------------------------------------------------------
static bool isBlank(const std::string& line) {
    for (char c : line) {
        if (!std::isspace(static_cast<unsigned char>(c))) return false;
    }
    return true;
}

int main(int argc, char* argv[]) {
    std::ifstream file;
    std::istream* input = &std::cin;
    if (argc >= 2) {
        file.open(argv[1]);
        if (!file) return 0;
        input = &file;
    }

    std::string line;
    while (std::getline(*input, line)) {
        if (!line.empty() && line.back() == '\r') line.pop_back();
        if (isBlank(line)) continue;

        try {
            Parser parser(tokenize(line));
            auto stmt = parser.parseStatement();
            Env env;                      // fresh env per line
            stmt->execute(env);
        } catch (const MiniCalcError& e) {
            std::cout << "ERROR:" << e.code() << '\n';
        } catch (...) {
            std::cout << "ERROR:PARSE\n";
        }
    }
    return 0;
}
