static int helper(int x);

int run(void)
{
	return helper(1);
}

static int helper(int x)
{
	return x * 2;
}
