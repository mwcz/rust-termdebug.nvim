fn fibonacci(n: u32) -> u32 {
    if n <= 1 {
        return n;
    }
    fibonacci(n - 1) + fibonacci(n - 2)
}

fn factorial(n: u32) -> u32 {
    if n == 0 {
        return 1;
    }
    n * factorial(n - 1)
}

fn main() {
    println!("Starting program");

    let fib_5 = fibonacci(5);
    println!("fibonacci(5) = {}", fib_5);

    let fact_5 = factorial(5);
    println!("factorial(5) = {}", fact_5);

    let sum = fib_5 + fact_5;
    println!("sum = {}", sum);

    println!("Program complete");
}
